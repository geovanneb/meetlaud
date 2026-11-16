package com.meetlaud.domain

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import java.io.File
import java.time.Instant
import java.util.UUID

/**
 * A Swift actor on the JVM: one coroutine at a time on its own lane, and others may run while it suspends, as an
 * actor allows at each await.
 */
@OptIn(ExperimentalCoroutinesApi::class)
fun actorLane(): CoroutineDispatcher = Dispatchers.Default.limitedParallelism(1)

/** UserDefaults: small settings that survive relaunches. SharedPreferences on Android, a map in tests. */
interface Preferences {
    fun string(key: String): String?
    fun setString(key: String, value: String?)
    fun bool(key: String): Boolean?
    fun setBool(key: String, value: Boolean)
    fun double(key: String): Double?
    fun setDouble(key: String, value: Double)
    fun stringList(key: String): List<String>?
    fun setStringList(key: String, value: List<String>?)
    fun remove(key: String)
    /** Every key, for erasing everything. */
    fun clear()
    /** Fires with the key that changed. */
    val changes: Flow<String>
}

data class LanguageRequest(val system: String, val prompt: String, val maxTokens: Int, val temperature: Float = 0.3f)

/** What a language model's speed test measured. Writing speed has no bearing on how good the text is. */
data class LanguageSpeed(val modelID: String, val tokensPerSecond: Double, val firstTokenSeconds: Double) {
    /** About three quarters of a word per token in English, which is close enough for one rounded number. */
    val wordsPerMinute: Int get() = Math.round(tokensPerSecond * 45 / 10).toInt() * 10
}

/** Writes text. Every model in the app sits behind this. */
interface LanguageModelEngine : ModelRunner {
    fun generate(request: LanguageRequest): Flow<String>
}

/** Captures microphone audio into raw segments inside a directory. */
interface AudioCaptureEngine {
    val events: Flow<CaptureEvent>
    suspend fun start(directory: File)
    /** Stops writing. The microphone stays open, so the app stays alive and can resume. */
    suspend fun pause()
    suspend fun resume()
    /** Closes the audio so that every sample written is on disk. */
    suspend fun stop()
    /** Releases the audio session. Called after the final file is saved. */
    suspend fun deactivate()
    suspend fun availableInputs(): List<AudioInput>
    suspend fun selectInput(input: AudioInput)
}

/** Turns raw segments into the final audio file. */
interface AudioAssembler {
    /** Returns the duration of the file written. Must not delete the segments. */
    suspend fun assemble(segments: File, into: File): TimeInterval
}

interface RecordingStore {
    suspend fun insert(recording: Recording)
    suspend fun update(recording: Recording)
    suspend fun delete(id: RecordingID)
    suspend fun recording(id: RecordingID): Recording?
    suspend fun recordings(status: RecordingStatus): List<Recording>
    suspend fun insert(marker: Marker)
    suspend fun markers(id: RecordingID): List<Marker>
    suspend fun insert(pause: PauseSpan)
    suspend fun pauses(id: RecordingID): List<PauseSpan>
    suspend fun trashedRecordings(): List<Recording>
    /** Matches titles and notes in recordings that are not in the trash. */
    suspend fun search(query: String): List<SearchHit>
    /** Emits the full list now and after every change, trash included. */
    fun observeRecordings(): Flow<List<Recording>>

    suspend fun insert(folder: Folder)
    suspend fun update(folder: Folder)
    /** Recordings inside return to the main list. */
    suspend fun deleteFolder(id: FolderID)
    fun observeFolders(): Flow<List<Folder>>
}

/** Reads and writes finished audio files, as opposed to capturing them. */
interface AudioProcessor {
    /** Converts any supported audio or video file into the app's audio format. Returns the duration. */
    suspend fun importAudio(source: File, file: File): TimeInterval
    /** Joins files in order. Returns the total duration. Does not touch the originals. */
    suspend fun merge(sources: List<File>, file: File): TimeInterval
}

interface CalendarProvider {
    val access: CalendarAccess
    suspend fun requestAccess(): Boolean
    /** Timed events in a period, soonest first. All-day, cancelled, and declined events stay out. */
    suspend fun events(from: Instant, to: Instant): List<CalendarEvent>
    /** Every calendar on the device, grouped by account. Empty without access. */
    suspend fun calendars(): List<CalendarSource>
}

interface RecordingFiles {
    fun segmentsDirectory(id: RecordingID): File
    fun audioFile(id: RecordingID): File
    fun attachmentsDirectory(id: RecordingID): File
    /** Creates the recording's folder, for when audio arrives without segments. */
    fun prepare(id: RecordingID)
    fun copyAttachment(name: String, source: RecordingID, destination: RecordingID)
    fun removeSegments(id: RecordingID)
    fun removeAll(id: RecordingID)
    fun hasSegments(id: RecordingID): Boolean
    fun availableBytes(): Long
}

/** The system surface that shows the recording outside the app: the ongoing notification on Android. */
interface RecordingActivityPresenter {
    suspend fun begin(title: String)
    suspend fun update(status: CaptureStatus, recorded: TimeInterval)
    suspend fun end()
}

interface MicrophonePermission {
    val access: MicrophoneAccess
    suspend fun request(): Boolean
}

interface AudioPlaying {
    val duration: TimeInterval
    val currentTime: TimeInterval
    val isPlaying: Boolean
    var rate: Float
    fun load(file: File, title: String)
    fun play()
    fun pause()
    fun seek(time: TimeInterval)
    fun stop()
}

interface ModelCatalog {
    val models: List<ModelDescriptor>
}

/** Puts model files on the device. This is the only way anything in the app reaches the network. */
interface ModelInstaller {
    val events: Flow<Pair<String, InstallState>>
    suspend fun state(id: String): InstallState
    suspend fun installedIDs(): Set<String>
    suspend fun install(model: ModelDescriptor, allowsCellular: Boolean)
    suspend fun pause(id: String)
    suspend fun cancel(id: String)
    suspend fun remove(id: String)
    fun folder(id: String): File?
    /** Reconnects to downloads that continued while the app was closed. */
    suspend fun reconnect()
}

interface ModelUsageStore {
    suspend fun selection(role: ModelRole): SelectionMode
    suspend fun setSelection(mode: SelectionMode, role: ModelRole)
    suspend fun insert(stat: ModelRunStat)
    suspend fun stats(): List<ModelRunStat>
    suspend fun logNetwork(entry: NetworkLogEntry)
    suspend fun networkLog(): List<NetworkLogEntry>
    /** Only the person can do this, from Network activity. The app never trims the log by itself. */
    suspend fun clearNetworkLog()
}

data class NetworkLogEntry(
    val id: UUID = UUID.randomUUID(),
    val host: String,
    val modelID: String,
    val bytes: Long,
    val date: Instant,
)

interface DeviceMonitor {
    suspend fun profile(): DeviceProfile
    suspend fun condition(): DeviceCondition
    /** Fires when something relevant changes. There is no polling behind this. */
    val changes: Flow<Unit>
}

// MARK: - System

/**
 * Decides when the app is locked and covered. Unlocking itself pauses the app, which would otherwise lock it again
 * the moment it unlocks, so only the background locks.
 */
data class AppLockState(
    val isEnabled: Boolean,
    val isLocked: Boolean = isEnabled,
    /** The app switcher takes its picture on the way out, so the content has to be gone before that. */
    val isCovered: Boolean = isEnabled,
    private val isAuthenticating: Boolean = false,
    private val hasPrompted: Boolean = false,
) {
    fun setEnabled(enabled: Boolean): AppLockState =
        if (enabled) copy(isEnabled = true) else copy(isEnabled = false, isLocked = false, isCovered = false)

    fun becameInactive(): AppLockState = copy(isCovered = isEnabled)

    fun enteredBackground(): AppLockState =
        if (!isEnabled) this else copy(isLocked = true, isCovered = true, hasPrompted = false)

    /** Returns the new state, and whether to ask for authentication now. Asks once; after a cancel, Unlock asks again. */
    fun becameActive(): Pair<AppLockState, Boolean> {
        if (!isLocked) return copy(isCovered = false) to false
        if (isAuthenticating || hasPrompted) return this to false
        return copy(hasPrompted = true, isAuthenticating = true) to true
    }

    /** For the Unlock button. False while a prompt is already up. */
    fun requestUnlock(): Pair<AppLockState, Boolean> {
        if (!isLocked || isAuthenticating) return this to false
        return copy(isAuthenticating = true) to true
    }

    fun finishAuthentication(success: Boolean): AppLockState =
        if (success) copy(isAuthenticating = false, isLocked = false, isCovered = false) else copy(isAuthenticating = false)
}

object AppLockPreferences {
    const val ENABLED_KEY = "privacy.appLock"
}

interface DeviceAuthenticator {
    /** False when the device has no screen lock, in which case a lock could never be opened again. */
    val isAvailable: Boolean
    suspend fun authenticate(reason: String): Boolean
}

object NotificationPreferences {
    const val TRANSCRIPT_READY_KEY = "notifications.transcriptReady"
    const val EVENT_REMINDERS_KEY = "notifications.eventReminders"
    /** Seconds before a meeting. */
    const val REMINDER_LEAD: TimeInterval = 10.0 * 60
}

interface LocalNotifier {
    suspend fun requestAccess(): Boolean
    suspend fun notify(id: String, title: String, body: String)
    /** Replaces every reminder set earlier. */
    suspend fun scheduleReminders(events: List<CalendarEvent>, title: String)
}

data class StorageUsage(
    val recordings: Long,
    val library: Long,
    val models: Long,
    val cache: Long,
    /** Space still free on the device. Null in tests and when it cannot tell. */
    val available: Long? = null,
) {
    val total: Long get() = recordings + library + models + cache
}

object StoragePreferences {
    const val BACKUP_INCLUDED_KEY = "storage.backupIncluded"
}

interface StorageManaging {
    fun usage(): StorageUsage
    fun clearCache()
    /** Models stay out either way: they can be downloaded again, and they are huge. */
    fun setBackupIncluded(included: Boolean)
    /** Removes every recording, attachment, and leftover file. The database is the store's job. */
    fun removeEverything()
}

enum class ArchiveError { WRONG_PASSWORD, DAMAGED, INCOMPATIBLE }

class ArchiveException(val error: ArchiveError) : Exception(error.name)

/** Copies the database out and back in. Lives next to the database, since nothing else may touch it. */
interface DatabaseSnapshots {
    suspend fun writeSnapshot(file: File, includingVoicePrints: Boolean)
    /** Replaces everything in the live database. Throws before changing anything if it cannot be read. */
    suspend fun restoreSnapshot(file: File)
    suspend fun eraseEverything()
}

interface LibraryArchiver {
    suspend fun export(file: File, password: String, includingVoicePrints: Boolean, progress: (Double) -> Unit)
    /** Replaces the library with the archive's. Nothing changes unless the whole file reads correctly. */
    suspend fun restore(file: File, password: String, progress: (Double) -> Unit)
}

// MARK: - Recording snapshot

sealed interface CaptureStatus {
    data object Idle : CaptureStatus
    data object Recording : CaptureStatus
    data class Paused(val reason: PauseReason) : CaptureStatus
    /** Encoding the final file. The audio is already safe on disk. */
    data object Finishing : CaptureStatus

    val isActive: Boolean get() = this != Idle
}

/** Everything the interface needs to draw the recording in progress. */
data class RecordingSnapshot(
    val status: CaptureStatus = CaptureStatus.Idle,
    val recordingID: RecordingID? = null,
    val title: String = "",
    val recorded: TimeInterval = 0.0,
    /** Audio level from 0 to 1. */
    val level: Float = 0f,
    val markers: List<Marker> = emptyList(),
    val isStorageLow: Boolean = false,
    /** The system ended the interruption but would not let capture resume on its own. */
    val needsManualResume: Boolean = false,
)

data class AudioInput(val id: String, val name: String)

sealed interface CaptureEvent {
    data class Progress(val recorded: TimeInterval, val level: Float) : CaptureEvent
    data object InterruptionBegan : CaptureEvent
    data class InterruptionEnded(val shouldResume: Boolean) : CaptureEvent
    data class Failed(val message: String) : CaptureEvent
}

enum class MicrophoneAccess { UNDETERMINED, GRANTED, DENIED }
