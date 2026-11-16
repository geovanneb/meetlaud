package com.meetlaud.domain

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Duration
import java.time.Instant

/** Runs transcription jobs, one at a time, and keeps them safe across crashes, heat, and closed apps. */
class TranscriptionCoordinator(
    internal val store: TranscriptStore,
    private val usage: ModelUsageStore,
    private val recordings: RecordingStore,
    internal val files: RecordingFiles,
    internal val source: AudioWindowSource,
    private val device: DeviceMonitor,
    internal val lease: BackgroundWorkLease,
    internal val arbiter: ModelArbiter,
    internal val speakers: SpeakerPipeline? = null,
    private val vocabulary: () -> List<VocabularyEntry> = { emptyList() },
    private val onFinished: suspend (RecordingID) -> Unit = {},
    internal val models: (String) -> Pair<ModelDescriptor, File?>?,
    private val engines: (ModelRuntime) -> TranscriptionEngine?,
    internal val now: () -> Instant = { Instant.now() },
) {
    private val lane = actorLane()
    private val scope = CoroutineScope(SupervisorJob() + lane)

    private val progressFlow = MutableStateFlow<Map<RecordingID, JobProgress>>(emptyMap())
    val updates: StateFlow<Map<RecordingID, JobProgress>> = progressFlow.asStateFlow()
    internal var progress: Map<RecordingID, JobProgress>
        get() = progressFlow.value
        set(value) { progressFlow.value = value }

    private var worker: Job? = null
    private var deviceWatcher: Job? = null
    internal var loaded: Pair<ModelRuntime, String>? = null
    /** Jobs the engine failed on, even after a second try. They wait for `retryHeld()`. */
    internal val held = HashSet<RecordingID>()
    /** Whether the current job ends by separating voices, so screens can show that step from the start. */
    internal var includesSpeakers = false

    val currentProgress: Map<RecordingID, JobProgress> get() = progress

    private suspend fun <T> isolated(block: suspend () -> T): T = withContext(lane) { block() }

    // MARK: - Queue

    /**
     * Starts over with this model. An earlier transcript is replaced once the first text is saved. `whenCharging`
     * holds the job until the device is on a charger and not hot.
     */
    suspend fun enqueue(id: RecordingID, modelID: String, language: String?, whenCharging: Boolean = false) = isolated {
        keepCurrentTranscript(id)
        store.deleteTranscript(id)
        val job = TranscriptionJob(id, modelID, language, state = if (whenCharging) JobState.WAITING_FOR_POWER else JobState.QUEUED)
        store.save(job)
        store.save(Transcript(id, modelID, language, isComplete = false))
        report(id, if (whenCharging) JobProgress.Phase.WAITING_FOR_POWER else JobProgress.Phase.QUEUED, 0.0)
        if (whenCharging) resumePausedIfPossible() else startWorkerIfNeeded()
    }

    suspend fun cancel(id: RecordingID) = isolated {
        held.remove(id)
        store.deleteJob(id)
        progress = progress - id
    }

    /** Runs at launch. A job still marked as running means that the app died in the middle of it. */
    suspend fun resumeInterrupted(countKills: Boolean = true) = isolated {
        for (stored in store.jobs()) {
            var job = stored
            if (job.state == JobState.RUNNING) {
                if (countKills) usage.insert(ModelRunStat(job.modelID, 0.0, 0.0, ModelRunStat.Outcome.KILLED, now()))
                job = job.copy(state = JobState.QUEUED)
                store.save(job)
            }
            val duration = runCatching { source.duration(files.audioFile(job.recordingID)) }.getOrDefault(0.0)
            report(
                job.recordingID,
                if (job.state == JobState.WAITING_FOR_POWER) JobProgress.Phase.WAITING_FOR_POWER else JobProgress.Phase.QUEUED,
                if (duration > 0) minOf(job.checkpoint / duration, 1.0) else 0.0,
            )
        }
        resumePausedIfPossible()
    }

    private fun startWorkerIfNeeded() {
        watchDeviceIfNeeded()
        if (worker != null) return
        worker = scope.launch { drainQueue() }
    }

    private suspend fun drainQueue() {
        // Held for the whole queue, so that the model stays loaded between jobs and nothing else can unload it.
        arbiter.acquire()
        try {
            while (true) {
                val job = nextJob() ?: break
                try {
                    run(job)
                } catch (cancel: CancellationException) {
                    throw cancel
                } catch (error: TranscriptionException) {
                    if (error.error == TranscriptionError.MODEL_NOT_INSTALLED || error.error == TranscriptionError.MISSING_MODEL_FILES) {
                        // Nothing can bring the model back by itself. The text saved so far stays.
                        runCatching { store.deleteJob(job.recordingID) }
                        progress = progress - job.recordingID
                    } else {
                        hold(job)
                    }
                } catch (error: Exception) {
                    hold(job)
                }
            }
        } finally {
            withContext(kotlinx.coroutines.NonCancellable) {
                unloadEngine()
                arbiter.release()
                lease.end()
            }
            worker = null
        }
        // A job can arrive in the moment between the last check and clearing the worker.
        if (nextJob() != null) startWorkerIfNeeded()
    }

    private suspend fun nextJob(): TranscriptionJob? {
        val waiting = runCatching { store.jobs() }.getOrDefault(emptyList())
        return waiting.firstOrNull { (it.state == JobState.QUEUED || it.state == JobState.RUNNING) && it.recordingID !in held }
    }

    // MARK: - Running

    private suspend fun run(original: TranscriptionJob) {
        var job = original
        val id = job.recordingID
        val resolved = models(job.modelID) ?: throw TranscriptionException(TranscriptionError.MODEL_NOT_INSTALLED)
        val engine = engines(resolved.first.runtime) ?: throw TranscriptionException(TranscriptionError.MODEL_NOT_INSTALLED)
        val file = files.audioFile(id)
        val duration = source.duration(file)

        if (!waitForDevice(job, duration)) return

        job = job.copy(state = JobState.RUNNING)
        store.save(job)
        lease.begin(recordings.recording(id)?.title ?: "")

        includesSpeakers = speakers?.isAvailable() ?: false
        report(id, JobProgress.Phase.PREPARING, fraction(job, duration))
        if (loaded?.second != job.modelID) {
            unloadEngine()
            engine.prepare(resolved.first, resolved.second)
            loaded = resolved.first.runtime to job.modelID
        }

        val started = now()
        val startPosition = job.checkpoint
        val finished = transcribeWindows(job, engine, file, duration) ?: return
        // Done means the text reaches the end of the audio. Anything less is a job to finish.
        if (finished.checkpoint < duration - 1) throw TranscriptionException(TranscriptionError.AUDIO_UNAVAILABLE)

        separateSpeakers(id, file)
        store.save(Transcript(id, job.modelID, finished.language, isComplete = true))
        store.deleteJob(id)
        progress = progress - id
        usage.insert(
            ModelRunStat(job.modelID, duration - startPosition, Duration.between(started, now()).toMillis() / 1000.0, ModelRunStat.Outcome.COMPLETED, now()),
        )
        onFinished(id)
    }

    /** Speakers are a bonus on top of the text. A failure here must never cost the transcript. */
    private suspend fun separateSpeakers(id: RecordingID, file: File) {
        val speakers = speakers ?: return
        if (!speakers.isAvailable()) return
        // Two heavy models at once is how the system ends up killing the app.
        unloadEngine()
        report(id, JobProgress.Phase.SEPARATING_SPEAKERS, 1.0)
        try {
            speakers.run(id, file)
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (_: Exception) {
        }
    }

    /** Returns null when the job stopped early, by being cancelled or paused for heat. */
    private suspend fun transcribeWindows(original: TranscriptionJob, engine: TranscriptionEngine, file: File, duration: TimeInterval): TranscriptionJob? {
        var job = original
        val id = job.recordingID
        val folder = recordings.recording(id)?.folderID
        val vocabulary = vocabulary().applying(folder)
        val hints = TranscriptionHints.from(vocabulary)
        var stopped = false
        source.windows(file, job.checkpoint).collect { window ->
            if (stopped) return@collect
            currentCoroutineContext().ensureActive()
            if (store.job(id) == null) {
                stopped = true
                return@collect
            }
            // The model is ready once the first window starts, so the screen moves on from preparing now.
            report(id, JobProgress.Phase.TRANSCRIBING, fraction(job, duration))
            val result = transcribe(window, job, engine, hints, duration)

            job = job.copy(checkpoint = window.end, language = job.language ?: result.language)
            store.append(result.segments(window, id, vocabulary), job)

            val value = fraction(job, duration)
            report(id, JobProgress.Phase.TRANSCRIBING, value)
            lease.update(value)

            // Stopping between windows loses nothing, since each one is already saved.
            if (!RightNow.evaluate(device.condition()).allowsHeavyWork) {
                pause(job, duration)
                stopped = true
            }
        }
        return if (stopped) null else job
    }

    /** The one place progress changes. A phase keeps its start time while it lasts. */
    internal fun report(id: RecordingID, phase: JobProgress.Phase, value: Double) {
        val previous = progress[id]
        val continues = previous?.phase == phase
        progress = progress + (id to JobProgress(
            phase = phase,
            fraction = value,
            phaseStartedAt = if (continues) previous?.phaseStartedAt else now(),
            phaseStartFraction = if (continues) previous!!.phaseStartFraction else value,
            includesSpeakers = includesSpeakers || (previous?.includesSpeakers ?: false),
        ))
    }

    internal fun fraction(job: TranscriptionJob, duration: TimeInterval): Double =
        if (duration > 0) minOf(job.checkpoint / duration, 1.0) else 0.0

    internal suspend fun unloadEngine() {
        loaded?.let { engines(it.first)?.unload() }
        loaded = null
    }

    /** Frees memory when the system asks. The next window loads the model again. */
    suspend fun handleMemoryWarning() = isolated {
        if (worker == null) unloadEngine()
    }

    // MARK: - Waiting for the device

    private suspend fun waitForDevice(job: TranscriptionJob, duration: TimeInterval): Boolean {
        if (!RightNow.evaluate(device.condition()).allowsHeavyWork) {
            pause(job, duration)
            return false
        }
        return true
    }

    private suspend fun pause(job: TranscriptionJob, duration: TimeInterval) {
        val paused = job.copy(state = JobState.PAUSED)
        store.save(paused)
        report(job.recordingID, JobProgress.Phase.WAITING_FOR_DEVICE, fraction(paused, duration))
    }

    /** Jobs paused by heat come back by themselves when the device cools down. */
    private fun watchDeviceIfNeeded() {
        if (deviceWatcher != null) return
        deviceWatcher = scope.launch { device.changes.collect { resumePausedIfPossible() } }
    }

    /** Jobs waiting for a charger come back too, once there is one and the device is not hot. */
    internal suspend fun resumePausedIfPossible() {
        val condition = device.condition()
        val rightNow = RightNow.evaluate(condition)
        if (!rightNow.allowsHeavyWork) {
            watchDeviceIfNeeded()
            return
        }
        val powered = condition.isCharging && rightNow != RightNow.Limited(RightNow.Reason.HOT)
        for (job in runCatching { store.jobs() }.getOrDefault(emptyList())) {
            val updated = when {
                job.state == JobState.PAUSED -> job.copy(state = JobState.QUEUED)
                job.state == JobState.WAITING_FOR_POWER && powered -> {
                    report(job.recordingID, JobProgress.Phase.QUEUED, progress[job.recordingID]?.fraction ?: 0.0)
                    job.copy(state = JobState.QUEUED)
                }
                else -> continue
            }
            runCatching { store.save(updated) }
        }
        startWorkerIfNeeded()
    }

    // MARK: - When the engine fails

    /**
     * Tries again the jobs the engine failed on. Runs when the app comes to the front, since the usual cause is the
     * system holding back the hardware from an app in the background, or memory that is free again.
     */
    suspend fun retryHeld() = isolated {
        if (held.isEmpty()) return@isolated
        for (id in held) report(id, JobProgress.Phase.QUEUED, progress[id]?.fraction ?: 0.0)
        held.clear()
        resumePausedIfPossible()
    }

    /** Keeps a job the engine failed on, never marking its transcript as done. */
    internal suspend fun hold(original: TranscriptionJob) {
        val id = original.recordingID
        val job = (runCatching { store.job(id) }.getOrNull() ?: original).copy(state = JobState.QUEUED)
        runCatching { store.save(job) }
        held.add(id)
        unloadEngine()
        val duration = runCatching { source.duration(files.audioFile(id)) }.getOrDefault(0.0)
        report(id, JobProgress.Phase.INTERRUPTED, fraction(job, duration))
    }

    /** One window, tried a second time with the model loaded again. A failure never reaches the transcript as silence. */
    internal suspend fun transcribe(window: AudioWindow, job: TranscriptionJob, engine: TranscriptionEngine, hints: List<String>, duration: TimeInterval): WindowResult {
        val id = job.recordingID
        val onProgress: (Double) -> Unit = { part ->
            val position = window.start + (window.end - window.start) * part.coerceIn(0.0, 1.0)
            scope.launch { reportWithin(id, position, duration) }
        }
        return try {
            engine.transcribe(window, job.language, hints, onProgress)
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (error: Exception) {
            val resolved = models(job.modelID) ?: throw error
            unloadEngine()
            engine.prepare(resolved.first, resolved.second)
            loaded = resolved.first.runtime to job.modelID
            engine.transcribe(window, job.language, hints, onProgress)
        }
    }

    /** Progress from inside a window. It only ever moves the bar forward, and only while text is still being written. */
    private suspend fun reportWithin(id: RecordingID, position: TimeInterval, duration: TimeInterval) {
        val current = progress[id] ?: return
        if (duration <= 0 || current.phase != JobProgress.Phase.TRANSCRIBING) return
        val value = minOf(position / duration, 1.0)
        if (value <= current.fraction) return
        report(id, JobProgress.Phase.TRANSCRIBING, value)
        lease.update(value)
    }

    // MARK: - Speakers again

    /** Whether voices can be separated at all: a speaker model is installed. */
    suspend fun canSeparateSpeakers(): Boolean = speakers?.isAvailable() ?: false

    /**
     * Separates voices again on a finished transcript, for example with the number of people the person knows spoke.
     * The text stays as it is.
     */
    suspend fun redetectSpeakers(id: RecordingID, count: SpeakerCount) = isolated {
        val speakers = speakers ?: return@isolated
        if (!speakers.isAvailable()) return@isolated
        // A transcription still running for this meeting will separate voices itself.
        if (store.job(id) != null) return@isolated
        // Waits for any other heavy model, so that two are never loaded at once.
        arbiter.acquire()
        includesSpeakers = true
        report(id, JobProgress.Phase.SEPARATING_SPEAKERS, 1.0)
        try {
            speakers.run(id, files.audioFile(id), count)
        } finally {
            progress = progress - id
            arbiter.release()
        }
    }

    // MARK: - Versions

    /** Brings an earlier transcript back. The current one becomes a version, so that this can be undone. */
    suspend fun restore(version: TranscriptVersion) = isolated {
        val id = version.recordingID
        if (store.job(id) != null) return@isolated
        keepCurrentTranscript(id)
        store.deleteVersion(version.id)
        store.deleteTranscript(id)
        val job = TranscriptionJob(id, version.modelID, version.language)
        store.save(Transcript(id, version.modelID, version.language, isComplete = true))
        store.append(version.segments, job)
        store.deleteJob(id)
    }

    internal suspend fun keepCurrentTranscript(id: RecordingID) {
        val segments = store.segments(id)
        if (segments.isEmpty()) return
        val transcript = store.transcript(id) ?: return
        store.save(
            TranscriptVersion(
                recordingID = id, modelID = transcript.modelID, language = transcript.language, savedAt = now(),
                // Speakers belong to the transcript that replaces this one.
                segments = segments.map { TranscriptSegment(recordingID = id, start = it.start, end = it.end, text = it.text) },
            ),
        )
    }
}

private fun WindowResult.segments(window: AudioWindow, id: RecordingID, vocabulary: List<VocabularyEntry>): List<TranscriptSegment> =
    segments
        // Only punctuation is a model that heard no speech.
        .filter { TranscriptCleanup.hasWords(it.text) }
        .map {
            TranscriptSegment(
                recordingID = id,
                start = window.start + it.start,
                end = window.start + it.end,
                text = VocabularyCorrector.apply(vocabulary, TranscriptCleanup.markRepeats(it.text.trimmedWhitespace())),
            )
        }
