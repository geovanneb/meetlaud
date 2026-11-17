package com.meetlaud.app

import android.content.Context
import com.meetlaud.app.feature.home.HomeModel
import com.meetlaud.app.feature.library.LibraryController
import com.meetlaud.app.feature.recording.RecordingController
import com.meetlaud.app.infra.capture.AacAssembler
import com.meetlaud.app.infra.capture.LiveCaptureEngine
import com.meetlaud.app.infra.capture.LiveMicrophonePermission
import com.meetlaud.app.infra.capture.RecordingCommand
import com.meetlaud.app.infra.capture.RecordingCommandBridge
import com.meetlaud.app.infra.capture.RecordingNotificationPresenter
import com.meetlaud.domain.RecordingCoordinator
import com.meetlaud.domain.CaptureStatus
import com.meetlaud.app.routing.AppRoute
import kotlinx.coroutines.launch
import com.meetlaud.app.feature.shared.TranscriptionCenter
import com.meetlaud.app.feature.shared.AutoTranscribe
import com.meetlaud.app.infra.system.NoSystemAssets
import com.meetlaud.app.infra.engines.LlamaEmbeddingEngine
import com.meetlaud.app.infra.engines.LlamaLanguageEngine
import com.meetlaud.app.infra.engines.LlamaRunner
import com.meetlaud.app.infra.engines.WhisperCppEngine
import com.meetlaud.app.infra.modeldelivery.BundledCatalog
import com.meetlaud.app.infra.modeldelivery.ModelDownloader
import com.meetlaud.app.infra.system.ForegroundWork
import com.meetlaud.app.infra.system.WorkServiceLease
import com.meetlaud.domain.ModelRuntime
import com.meetlaud.app.infra.diarization.OnnxDiarizationEngine
import com.meetlaud.app.infra.playback.SystemAudioPlayer
import com.meetlaud.app.infra.system.ShareTasksProvider
import com.meetlaud.app.feature.detail.DetailModel
import com.meetlaud.app.feature.ask.AskController
import com.meetlaud.app.feature.shared.SkillLibrary
import com.meetlaud.domain.AskCoordinator
import com.meetlaud.domain.KnowledgeIndexer
import com.meetlaud.app.feature.shared.SummaryCenter
import com.meetlaud.domain.SpeakerPipeline
import com.meetlaud.domain.SpeakerService
import com.meetlaud.domain.SummaryCoordinator
import com.meetlaud.domain.ModelRole
import com.meetlaud.domain.RecordingID
import com.meetlaud.domain.SummaryPreferences
import com.meetlaud.app.infra.audio.SpeechWindowReader
import com.meetlaud.app.infra.audio.MediaAudioProcessor
import com.meetlaud.app.infra.device.SystemDeviceMonitor
import com.meetlaud.app.infra.persistence.DatabaseStore
import com.meetlaud.app.infra.persistence.LocalRecordingFiles
import com.meetlaud.app.infra.system.AppPreferences
import com.meetlaud.app.infra.system.Permissions
import com.meetlaud.app.infra.system.SystemCalendarProvider
import com.meetlaud.app.routing.AppRouter
import com.meetlaud.domain.CalendarChoices
import com.meetlaud.domain.ChosenCalendars
import com.meetlaud.domain.LibraryService
import com.meetlaud.domain.ModelArbiter
import com.meetlaud.domain.ModelManager
import com.meetlaud.domain.TranscriptionCoordinator
import com.meetlaud.domain.VocabularyPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.firstOrNull
import com.meetlaud.app.feature.settings.SystemController
import com.meetlaud.app.feature.shared.AppLockController
import com.meetlaud.app.feature.shared.Sharing
import com.meetlaud.app.infra.archive.LibraryArchive
import com.meetlaud.app.infra.system.SystemAuthenticator
import com.meetlaud.app.infra.system.SystemNotifier
import com.meetlaud.app.localization.L10n
import com.meetlaud.domain.NotificationPreferences
import java.util.UUID
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ProcessLifecycleOwner
import java.io.File

/** The composition root: builds the object graph once, at launch, as AppContainer.swift. */
class AppContainer(context: Context, showcase: Boolean) {
    init { ForegroundWork.install(context) }
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val router = AppRouter()
    val preferences = AppPreferences(context, if (showcase) "meetlaud-showcase" else "meetlaud")
    val permissions = Permissions(context, preferences)
    val files = LocalRecordingFiles(File(context.filesDir, if (showcase) "Showcase" else "Meetlaud"), context.cacheDir)
    val store = DatabaseStore(files.databaseFile)
    val device = SystemDeviceMonitor(context, files.root)
    val calendarChoices = CalendarChoices(preferences)
    val calendar = ChosenCalendars(SystemCalendarProvider(context, permissions), calendarChoices)
    val arbiter = ModelArbiter()
    val catalog = BundledCatalog(context)
    val downloader = ModelDownloader(context, files.modelsDirectory, catalog.models, files::availableBytes) { store.logNetwork(it) }
    private val whisper = WhisperCppEngine()
    private val diarizer = OnnxDiarizationEngine()
    /** The search model on the device, found again on every call: it can be downloaded or removed at any time. */
    private val searchModel: suspend () -> Pair<com.meetlaud.domain.ModelDescriptor, File?>? = {
        modelManager.model(ModelRole.SEARCH, null)?.let { it to downloader.folder(it.id) }
    }
    private val llama = LlamaRunner(LlamaLanguageEngine(), LlamaEmbeddingEngine { searchModel() })
    private val runners: (ModelRuntime) -> com.meetlaud.domain.ModelRunner? = { runtime ->
        when (runtime) {
            ModelRuntime.WHISPER_CPP -> whisper
            ModelRuntime.LLAMA_CPP -> llama
            ModelRuntime.ONNX -> diarizer
            else -> null
        }
    }
    private fun installedModel(id: String) = catalog.models.firstOrNull { it.id == id }?.let { it to downloader.folder(id) }

    val modelManager = ModelManager(
        catalog = catalog,
        installer = downloader,
        usage = store,
        device = device,
        assets = NoSystemAssets,
        arbiter = arbiter,
        defaults = preferences,
        engines = runners,
        preferredLanguages = { context.resources.configuration.locales.let { list -> List(list.size()) { list[it].language } } },
    )
    private val voiceModel: suspend () -> com.meetlaud.domain.ModelDescriptor? = { modelManager.model(ModelRole.SPEAKER_SEPARATION, null) }
    val speakerService = SpeakerService(store, { voiceModel()?.id })
    val speakerPipeline = SpeakerPipeline(store, store, diarizer) { voiceModel()?.let { it to modelManager.folder(it.id) } }
    val summaryQueue = SummaryCoordinator(
        store = store, transcripts = store, speakers = store, engine = llama, arbiter = arbiter,
        models = ::installedModel,
        profile = { preferences.string(SummaryPreferences.PROFILE_KEY)?.takeIf { it.isNotBlank() } },
    )
    val summaries = SummaryCenter(summaryQueue, modelManager, store, preferences, scope)
    val skills = SkillLibrary(preferences)
    /** Every connector in this build. See docs/connectors.md. */
    val connectors = com.meetlaud.connectors.ConnectorRegistry(emptyList())
    val knowledgeIndexer = KnowledgeIndexer(store, store, store, store, llama, arbiter)
    val askQueue = AskCoordinator(
        conversations = store, knowledge = store, recordings = store, transcripts = store, speakers = store, summaries = store,
        language = llama, embedder = llama, indexer = knowledgeIndexer, arbiter = arbiter,
        models = ::installedModel,
        profile = { preferences.string(SummaryPreferences.PROFILE_KEY)?.takeIf { it.isNotBlank() } },
        pauseOtherWork = { summaryQueue.suspend() },
        resumeOtherWork = { summaryQueue.resume() },
    )
    val ask = AskController(askQueue, knowledgeIndexer, store, store, modelManager, scope)
    val player = SystemAudioPlayer(context)
    val reminders = ShareTasksProvider(context)
    val transcriptions = TranscriptionCoordinator(
        store = store,
        usage = store,
        recordings = store,
        files = files,
        source = SpeechWindowReader(),
        device = device,
        lease = WorkServiceLease(),
        arbiter = arbiter,
        speakers = speakerPipeline,
        vocabulary = { VocabularyPreferences.load(preferences) },
        onFinished = {
            knowledgeIndexer.run()
            notifyTranscriptReady()
        },
        models = ::installedModel,
        engines = { runtime -> runners(runtime) as? com.meetlaud.domain.TranscriptionEngine },
    )
    val transcription = TranscriptionCenter(transcriptions, modelManager, scope)
    val home = HomeModel(store, calendar, calendarChoices, scope)
    val libraryService = LibraryService(store, files, MediaAudioProcessor())
    val library = LibraryController(libraryService, store, preferences, context, scope)
    val recordingCoordinator = RecordingCoordinator(if (showcase) ShowcaseCaptureEngine() else LiveCaptureEngine(context), store, files, AacAssembler(), RecordingNotificationPresenter(context))
    val recorder = RecordingController(recordingCoordinator, LiveMicrophonePermission(permissions), router, preferences, scope)
    val calendarProvider = SystemCalendarProvider(context, permissions)
    val people = com.meetlaud.app.feature.people.PeopleModel(store, speakerService, store)
    val models = com.meetlaud.app.feature.models.ModelsController(
        modelManager, store, scope,
        clip = { speedClip(context)?.let { SpeechWindowReader().windows(it, 0.0).firstOrNull() } },
        trialRecordings = { runCatching { store.recordings(com.meetlaud.domain.RecordingStatus.READY) }.getOrDefault(emptyList()).filter { it.deletedAt == null }.sortedByDescending { it.createdAt } },
        trialClip = { id -> runCatching { SpeechWindowReader().windows(files.audioFile(id), 0.0).firstOrNull() }.getOrNull() },
    )

    /** The speed test clip, copied out of the app's assets once, since the decoder reads files. */
    private fun speedClip(context: Context): File? = runCatching {
        File(context.cacheDir, "speed-test.m4a").apply {
            if (!exists()) context.assets.open("speed-test.m4a").use { input -> outputStream().use { input.copyTo(it) } }
        }
    }.getOrNull()
    val authenticator = SystemAuthenticator(context)
    val notifier = SystemNotifier(context, permissions)
    val lock = AppLockController(preferences, authenticator, { L10n.System.lockReason }, scope)
    val system = SystemController(files, LibraryArchive(files.root, store), notifier, preferences) { Sharing.exportFolder(context) }
    /** Whether a screen of the app is in front. Notifications are for when it is not. */
    @Volatile var isForeground = false
        private set
    private val versionName: String = context.packageManager.getPackageInfo(context.packageName, 0).let { "${it.versionName} (${it.longVersionCode})" }
    val versionText: String get() = versionName
    val licensesText: String by lazy { runCatching { context.assets.open("THIRD_PARTY_NOTICES.md").bufferedReader().readText() }.getOrDefault("") }

    init {
        if (showcase) {
            runBlocking { Showcase.seed(store, context.resources.configuration.locales[0].language) }
            // The showcase is for screenshots and tests, as iOS passes -models.hasSeenSetup YES to its UI tests.
            preferences.setBool("models.hasSeenSetup", true)
        }
        RecordingCommandBridge.handler = ::handle
        recorder.recover()
        system.connect(::pauseAllWork, ::resumeAllWork, ::eraseEverything)
        followLifecycle()
        // As on iOS: a new recording is transcribed at once when the person chose "Always".
        recorder.onSaved = { id ->
            if (AutoTranscribe.from(preferences.string(AutoTranscribe.STORAGE_KEY)) == AutoTranscribe.ALWAYS) {
                scope.launch { transcription.transcribe(id, null) }
            }
        }
        // Killed only counts as a failure if the person was here. Android ends background apps all the time.
        val wasActive = preferences.bool(ACTIVE_KEY) == true
        scope.launch { runCatching { transcriptions.resumeInterrupted(countKills = wasActive) } }
    }

    /**
     * The process, not an activity: rotating the phone rebuilds the activity, and that must not lock the app.
     * Pause is iOS's inactive (recent apps, a system dialog), stop is the background.
     */
    private fun followLifecycle() {
        ProcessLifecycleOwner.get().lifecycle.addObserver(LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> lock.becameActive()
                Lifecycle.Event.ON_PAUSE -> lock.becameInactive()
                Lifecycle.Event.ON_START -> setActive(true)
                Lifecycle.Event.ON_STOP -> {
                    lock.enteredBackground()
                    setActive(false)
                }
                else -> Unit
            }
        })
    }

    /** Leaving the app stops the models, and is when reminders are set, as setActive in AppContainer.swift. */
    fun setActive(active: Boolean) {
        preferences.setBool(ACTIVE_KEY, active)
        isForeground = active
        scope.launch {
            if (active) {
                transcriptions.retryHeld()
                summaryQueue.resume()
                knowledgeIndexer.run()
            } else {
                // Fresh events, not Home's last load: a calendar may have been turned off since.
                home.refreshEvents()
                scheduleReminders()
                askQueue.stopAndRelease()
                knowledgeIndexer.suspend()
                summaryQueue.suspend()
            }
        }
    }

    private suspend fun scheduleReminders() {
        val wanted = preferences.bool(NotificationPreferences.EVENT_REMINDERS_KEY) == true
        notifier.scheduleReminders(if (wanted) home.events.take(10) else emptyList(), L10n.System.eventReminderTitle)
    }

    /** Only when the app is out of sight, and with no meeting content: this shows on the lock screen. */
    private suspend fun notifyTranscriptReady() {
        if (isForeground || preferences.bool(NotificationPreferences.TRANSCRIPT_READY_KEY) != true) return
        notifier.notify(UUID.randomUUID().toString().uppercase(), L10n.System.transcriptReadyTitle, "")
    }

    /** Stops everything that touches the library. Refuses during a recording, which comes first. */
    private suspend fun pauseAllWork(): Boolean {
        if (recorder.snapshot.status.isActive) return false
        askQueue.stopAndRelease()
        knowledgeIndexer.suspend()
        summaryQueue.suspend()
        player.stop()
        return true
    }

    private suspend fun resumeAllWork() {
        summaryQueue.resume()
        knowledgeIndexer.run()
        runCatching { transcriptions.resumeInterrupted(countKills = false) }
    }

    private suspend fun eraseEverything() {
        for (job in store.jobs()) transcriptions.cancel(job.recordingID)
        store.eraseEverything()
        files.removeEverything()
        modelManager.removeAllModels()
        notifier.scheduleReminders(emptyList(), "")
        preferences.shared.edit().clear().commit()
        if (lock.state.isEnabled) lock.forgetLock()
    }

    /** Recordings that can be summarized, newest first. */
    suspend fun transcribedRecordings(): List<com.meetlaud.domain.Recording> {
        val all = runCatching { store.recordings(com.meetlaud.domain.RecordingStatus.READY) }.getOrDefault(emptyList())
        return all.sortedByDescending { it.createdAt }.take(30).filter { runCatching { store.transcript(it.id)?.isComplete }.getOrNull() == true }
    }

    fun detailModel(id: RecordingID, startTime: Double?) = DetailModel(
        id, startTime, store, files, player, libraryService, store, transcription, store, speakerService, summaries, reminders,
    )

    /** Commands from the notification, shortcuts, and tiles, as AppContainer+System.swift handles them. */
    fun handle(command: RecordingCommand) {
        val status = recorder.snapshot.status
        when (command) {
            RecordingCommand.TOGGLE_PAUSE -> if (status.isActive) recorder.togglePause()
            RecordingCommand.STOP -> if (status.isActive) recorder.stop()
            RecordingCommand.MARK -> if (status.isActive) recorder.flag()
            RecordingCommand.START -> if (!status.isActive) recorder.record()
            RecordingCommand.TOGGLE -> if (status.isActive && status != CaptureStatus.Finishing) recorder.stop() else if (!status.isActive) recorder.record()
            RecordingCommand.OPEN_LAST -> scope.launch {
                home.recordings.maxByOrNull { it.createdAt }?.let { router.open(AppRoute.Recording(it.id)) }
            }
        }
    }

    private companion object {
        const val ACTIVE_KEY = "app.wasActive"
    }
}
