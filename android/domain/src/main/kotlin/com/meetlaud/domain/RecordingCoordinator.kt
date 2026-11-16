package com.meetlaud.domain

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Duration
import java.time.Instant
import java.util.UUID

enum class RecordingError { ALREADY_RECORDING, NO_ACTIVE_RECORDING }

class RecordingException(val error: RecordingError) : Exception(error.name)

/**
 * Owns the life of a recording: capture, pauses, interruptions, markers, and saving. The rule behind every method:
 * state that matters reaches the database first, so that a crash at any point leaves something
 * `recoverInterrupted()` can finish.
 */
class RecordingCoordinator(
    private val engine: AudioCaptureEngine,
    private val store: RecordingStore,
    private val files: RecordingFiles,
    private val assembler: AudioAssembler,
    private val activity: RecordingActivityPresenter,
    private val now: () -> Instant = { Instant.now() },
) {
    object Limits {
        /** Warn the person. */
        const val LOW_STORAGE_BYTES = 500_000_000L
        /** Stop safely, while there is still room to save. */
        const val CRITICAL_STORAGE_BYTES = 100_000_000L
        /** Checking storage on every level update would be wasteful. */
        const val STORAGE_CHECK_INTERVAL: TimeInterval = 5.0
        /** The ongoing notification updates by itself; the app refreshes it only this often. */
        const val ACTIVITY_UPDATE_INTERVAL: TimeInterval = 30.0
    }

    private val lane = actorLane()
    private val scope = CoroutineScope(SupervisorJob() + lane)
    private val state = MutableStateFlow(RecordingSnapshot())
    val snapshots: StateFlow<RecordingSnapshot> = state.asStateFlow()
    private var snapshot: RecordingSnapshot
        get() = state.value
        set(value) { state.value = value }

    private var current: Recording? = null
    private var pausedAt: Instant? = null
    private var lastStorageCheck: TimeInterval = 0.0
    private var lastActivityUpdate: TimeInterval = 0.0
    private var listener: Job? = null

    val currentSnapshot: RecordingSnapshot get() = snapshot

    private suspend fun <T> isolated(block: suspend () -> T): T = withContext(lane) { block() }

    // MARK: - Capture

    suspend fun start(title: String, attendees: List<String> = emptyList()): RecordingID = isolated {
        if (snapshot.status.isActive) throw RecordingException(RecordingError.ALREADY_RECORDING)
        listenToEngineIfNeeded()

        val recording = Recording(title = title, createdAt = now(), status = RecordingStatus.CAPTURING, attendees = attendees)
        store.insert(recording)
        try {
            engine.start(files.segmentsDirectory(recording.id))
        } catch (error: Exception) {
            runCatching { store.delete(recording.id) }
            runCatching { files.removeAll(recording.id) }
            throw error
        }

        current = recording
        lastStorageCheck = 0.0
        lastActivityUpdate = 0.0
        snapshot = RecordingSnapshot(
            status = CaptureStatus.Recording,
            recordingID = recording.id,
            title = title,
            isStorageLow = files.availableBytes() < Limits.LOW_STORAGE_BYTES,
        )
        activity.begin(title)
        recording.id
    }

    suspend fun pause() = isolated {
        if (snapshot.status != CaptureStatus.Recording) return@isolated
        engine.pause()
        pausedAt = now()
        snapshot = snapshot.copy(status = CaptureStatus.Paused(PauseReason.USER))
        activity.update(snapshot.status, snapshot.recorded)
    }

    suspend fun resume() = isolated { resumeInside() }

    private suspend fun resumeInside() {
        val status = snapshot.status as? CaptureStatus.Paused ?: return
        engine.resume()
        recordPause(status.reason)
        snapshot = snapshot.copy(status = CaptureStatus.Recording, needsManualResume = false)
        activity.update(snapshot.status, snapshot.recorded)
    }

    suspend fun stop(): Recording = isolated { stopInside() }

    private suspend fun stopInside(): Recording {
        var recording = current
        if (recording == null || !snapshot.status.isActive || snapshot.status == CaptureStatus.Finishing) {
            throw RecordingException(RecordingError.NO_ACTIVE_RECORDING)
        }
        (snapshot.status as? CaptureStatus.Paused)?.let { recordPause(it.reason) }
        snapshot = snapshot.copy(status = CaptureStatus.Finishing)
        activity.update(CaptureStatus.Finishing, snapshot.recorded)

        try {
            // A failure here leaves the recording in `capturing` with its segments, for recovery.
            engine.stop()
            val duration = assembler.assemble(files.segmentsDirectory(recording.id), files.audioFile(recording.id))
            recording = recording.copy(duration = maxOf(0.0, duration), status = RecordingStatus.READY)
            store.update(recording)
            runCatching { files.removeSegments(recording.id) }
        } catch (error: Exception) {
            engine.deactivate()
            activity.end()
            current = null
            snapshot = RecordingSnapshot()
            throw error
        }
        engine.deactivate()
        activity.end()
        current = null
        snapshot = RecordingSnapshot()
        return recording
    }

    // MARK: - Markers

    suspend fun addMarker(kind: MarkerKind, text: String? = null, attachment: String? = null): Marker = isolated {
        val current = current ?: throw RecordingException(RecordingError.NO_ACTIVE_RECORDING)
        val marker = Marker(recordingID = current.id, time = snapshot.recorded, kind = kind, text = text, attachment = attachment)
        store.insert(marker)
        snapshot = snapshot.copy(markers = snapshot.markers + marker)
        marker
    }

    /** Saves the photo first, so that a marker never points to a missing file. */
    suspend fun addPhoto(data: ByteArray): Marker {
        val id = isolated { current?.id } ?: throw RecordingException(RecordingError.NO_ACTIVE_RECORDING)
        val name = "${UUID.randomUUID().uuidString}.jpg"
        val directory = files.attachmentsDirectory(id)
        val temporary = File(directory, "$name.part")
        temporary.writeBytes(data)
        temporary.renameTo(File(directory, name))
        return addMarker(MarkerKind.PHOTO, attachment = name)
    }

    // MARK: - Input

    suspend fun availableInputs(): List<AudioInput> = engine.availableInputs()

    suspend fun selectInput(input: AudioInput) = engine.selectInput(input)

    // MARK: - Recovery

    /** Finishes recordings that a crash left behind. Returns the ones it saved. */
    suspend fun recoverInterrupted(): List<Recording> = isolated {
        val recovered = mutableListOf<Recording>()
        for (recording in store.recordings(RecordingStatus.CAPTURING)) {
            if (recording.id == current?.id) continue
            if (!files.hasSegments(recording.id)) {
                store.delete(recording.id)
                runCatching { files.removeAll(recording.id) }
                continue
            }
            val duration = try {
                assembler.assemble(files.segmentsDirectory(recording.id), files.audioFile(recording.id))
            } catch (_: Exception) {
                // Keep the segments. A later launch, or a future version, can try again.
                continue
            }
            val saved = recording.copy(duration = maxOf(0.0, duration), status = RecordingStatus.READY, wasRecovered = true)
            store.update(saved)
            runCatching { files.removeSegments(saved.id) }
            recovered.add(saved)
        }
        recovered
    }

    // MARK: - Engine events

    private fun listenToEngineIfNeeded() {
        if (listener != null) return
        listener = scope.launch { engine.events.collect { handle(it) } }
    }

    private suspend fun handle(event: CaptureEvent) {
        if (current == null) return
        when (event) {
            is CaptureEvent.Progress -> handleProgress(event.recorded, event.level)
            CaptureEvent.InterruptionBegan -> handleInterruptionBegan()
            is CaptureEvent.InterruptionEnded -> handleInterruptionEnded()
            is CaptureEvent.Failed -> {
                // The samples already written are safe. Stopping saves them, instead of pretending to record.
                handleInterruptionBegan()
                snapshot = snapshot.copy(needsManualResume = true)
            }
        }
    }

    private suspend fun handleProgress(recorded: TimeInterval, level: Float) {
        snapshot = snapshot.copy(recorded = recorded, level = level)
        if (recorded - lastActivityUpdate >= Limits.ACTIVITY_UPDATE_INTERVAL) {
            lastActivityUpdate = recorded
            activity.update(snapshot.status, recorded)
        }
        if (recorded - lastStorageCheck < Limits.STORAGE_CHECK_INTERVAL) return
        lastStorageCheck = recorded
        val available = files.availableBytes()
        snapshot = snapshot.copy(isStorageLow = available < Limits.LOW_STORAGE_BYTES)
        if (available < Limits.CRITICAL_STORAGE_BYTES) runCatching { stopInside() }
    }

    private suspend fun handleInterruptionBegan() {
        if (snapshot.status != CaptureStatus.Recording) return
        pausedAt = now()
        snapshot = snapshot.copy(status = CaptureStatus.Paused(PauseReason.INTERRUPTION))
        activity.update(snapshot.status, snapshot.recorded)
    }

    private suspend fun handleInterruptionEnded() {
        if (snapshot.status != CaptureStatus.Paused(PauseReason.INTERRUPTION)) return
        // Try even when the system does not suggest it. The worst outcome is showing Resume.
        try {
            resumeInside()
        } catch (_: Exception) {
            snapshot = snapshot.copy(needsManualResume = true)
            activity.update(snapshot.status, snapshot.recorded)
        }
    }

    private suspend fun recordPause(reason: PauseReason) {
        val current = current ?: return
        val pausedAt = pausedAt ?: return
        this.pausedAt = null
        val pause = PauseSpan(current.id, snapshot.recorded, Duration.between(pausedAt, now()).toMillis() / 1000.0, reason)
        runCatching { store.insert(pause) }
    }
}
