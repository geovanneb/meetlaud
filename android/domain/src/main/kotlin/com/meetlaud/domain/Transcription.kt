package com.meetlaud.domain

import kotlinx.coroutines.flow.Flow
import java.io.File
import java.time.Duration
import java.time.Instant
import java.util.UUID

data class TranscriptSegment(
    val id: UUID = UUID.randomUUID(),
    val recordingID: RecordingID,
    val start: TimeInterval,
    val end: TimeInterval,
    val text: String,
    val speaker: String? = null,
)

data class Transcript(
    val recordingID: RecordingID,
    val modelID: String,
    val language: String?,
    val isComplete: Boolean,
)

enum class JobState(val raw: String) {
    QUEUED("queued"), RUNNING("running"), PAUSED("paused"),
    /** The person chose to start it once the device is on a charger. */
    WAITING_FOR_POWER("waitingForPower");

    companion object {
        fun from(raw: String): JobState? = entries.firstOrNull { it.raw == raw }
    }
}

/** Work that survives the app closing. `checkpoint` is the audio position already saved. */
data class TranscriptionJob(
    val recordingID: RecordingID,
    val modelID: String,
    val language: String?,
    val checkpoint: TimeInterval = 0.0,
    val state: JobState = JobState.QUEUED,
)

/** A stretch of audio, already at 16 kHz mono, small enough to hold in memory. */
class AudioWindow(val start: TimeInterval, val end: TimeInterval, val samples: FloatArray)

/** A piece of speech. Times are relative to the window it came from. */
data class SpeechSegment(val start: TimeInterval, val end: TimeInterval, val text: String)

data class WindowResult(val segments: List<SpeechSegment>, val language: String?)

enum class TranscriptionError { MODEL_NOT_INSTALLED, MISSING_MODEL_FILES, LANGUAGE_NOT_SUPPORTED, AUDIO_UNAVAILABLE, ENGINE_FAILED }

class TranscriptionException(val error: TranscriptionError) : Exception(error.name)

/** Loads and frees a model. Every engine is one. */
interface ModelRunner {
    /** Loads the model. */
    suspend fun prepare(model: ModelDescriptor, folder: File?)
    /** Frees the memory. */
    suspend fun unload()
}

/** Turns speech into text. Every engine in the app sits behind this, and passes the same contract tests. */
interface TranscriptionEngine : ModelRunner {
    /**
     * @param hints Names and terms likely to be said, such as the person's vocabulary. A nudge, never inserted as text.
     * @param progress How much of this window is done, from 0 to 1, for engines that can tell.
     */
    suspend fun transcribe(window: AudioWindow, language: String?, hints: List<String> = emptyList(), progress: (Double) -> Unit = {}): WindowResult
}

/** What the engines are told to expect. Short on purpose: Whisper reads about 220 tokens of prompt at most. */
object TranscriptionHints {
    const val LIMIT = 40

    fun from(vocabulary: List<VocabularyEntry>): List<String> {
        val seen = HashSet<String>()
        return vocabulary
            .map { it.written.trimmedWhitespace() }
            .filter { it.isNotEmpty() && seen.add(it.lowercase()) }
            .take(LIMIT)
    }
}

/** Reads a file as a sequence of windows, so that memory stays flat however long the meeting is. */
interface AudioWindowSource {
    suspend fun duration(file: File): TimeInterval
    fun windows(file: File, from: TimeInterval): Flow<AudioWindow>
}

/** A transcript that was replaced. Changing models must never cost someone text they already had. */
data class TranscriptVersion(
    val id: UUID = UUID.randomUUID(),
    val recordingID: RecordingID,
    val modelID: String,
    val language: String?,
    val savedAt: Instant,
    val segments: List<TranscriptSegment>,
) {
    companion object {
        /** Older ones go first. A safety net and not an archive. */
        const val LIMIT = 3
    }
}

interface TranscriptStore {
    /** Newest first. */
    suspend fun versions(id: RecordingID): List<TranscriptVersion>
    /** Keeps only the newest `TranscriptVersion.LIMIT`. */
    suspend fun save(version: TranscriptVersion)
    suspend fun deleteVersion(id: UUID)
    suspend fun transcript(id: RecordingID): Transcript?
    suspend fun save(transcript: Transcript)
    suspend fun segments(id: RecordingID): List<TranscriptSegment>
    /** Saves a window's text and its checkpoint in one transaction, so that a crash can never repeat or lose text. */
    suspend fun append(segments: List<TranscriptSegment>, job: TranscriptionJob)
    suspend fun update(segment: TranscriptSegment)
    /** Covers phrases and speaker names. Returns how many changed. */
    suspend fun replaceAll(id: RecordingID, text: String, replacement: String): Int
    suspend fun deleteTranscript(id: RecordingID)

    suspend fun job(id: RecordingID): TranscriptionJob?
    suspend fun jobs(): List<TranscriptionJob>
    suspend fun save(job: TranscriptionJob)
    suspend fun deleteJob(id: RecordingID)
}

/** Lets long work continue when the person leaves the app: a foreground service on Android. */
interface BackgroundWorkLease {
    suspend fun begin(title: String)
    suspend fun update(progress: Double)
    suspend fun end()
}

data class JobProgress(
    val phase: Phase,
    /** From 0 to 1. */
    val fraction: Double,
    /** When this phase began, so a screen can show that time is passing even when the fraction cannot move. */
    val phaseStartedAt: Instant? = null,
    /** The fraction when this phase began. A resumed job starts partway, and only the work since then tells speed. */
    val phaseStartFraction: Double = fraction,
    /** Whether voices are separated after the text, so a screen can show that step before it starts. */
    val includesSpeakers: Boolean = false,
) {
    enum class Phase {
        QUEUED, PREPARING, TRANSCRIBING, SEPARATING_SPEAKERS, WAITING_FOR_DEVICE, WAITING_FOR_POWER,
        /** The engine failed on part of the audio, twice. The text so far is kept. */
        INTERRUPTED,
    }

    /** Whether the fraction says something now. */
    val isMeasurable: Boolean get() = phase == Phase.TRANSCRIBING

    /** Time left, from the speed of this run so far. Null until there is enough to measure. */
    fun estimatedRemaining(now: Instant): TimeInterval? {
        if (phase != Phase.TRANSCRIBING || phaseStartedAt == null) return null
        val done = fraction - phaseStartFraction
        val elapsed = Duration.between(phaseStartedAt, now).toMillis() / 1000.0
        if (done < 0.05 || elapsed < 5 || fraction >= 1) return null
        return elapsed / done * (1 - fraction)
    }
}
