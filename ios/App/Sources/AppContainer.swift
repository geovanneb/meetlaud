import AppRouting
import ASRApple
import ASRWhisperKit
import AudioCapture
import AudioEditing
import AudioPlayback
import ConnectorGTD
import Connectors
import DeviceMonitoring
import DiarizationFluid
import Domain
import FeatureAsk
import FeatureDetail
import FeatureHome
import FeatureLibrary
import FeatureModels
import FeaturePeople
import FeatureRecording
import FeatureSettings
import FeatureShared
import Foundation
import LLMMLX
import Localization
import ModelDelivery
import Persistence
import SystemBridges
import TestSupport
import UIKit

/// The composition root: builds the object graph once, at launch.
@MainActor
final class AppContainer {
    let router = AppRouter()
    let store: any RecordingStore
    let files: any RecordingFiles
    let player = SystemAudioPlayer()
    let recorder: RecordingController
    let home: HomeModel
    let library: LibraryController
    let models: ModelsController
    let transcription: TranscriptionCenter
    let people: PeopleModel
    let summaries: SummaryCenter
    let skills = SkillLibrary()
    /// Every connector in this build. See docs/connectors.md.
    let connectors = ConnectorRegistry([GetThingsDoneConnector()])
    lazy var connectorSync = ConnectorSync(
        registry: connectors,
        source: LibraryConnectorSource(
            store: services.store, transcripts: services.transcripts, speakers: services.speakers,
            files: services.files, usage: services.usage,
        ),
        log: UserDefaultsDeliveryLog(),
    )
    let summaryQueue: SummaryCoordinator
    let gate = GenerationGate()
    let ask: AskController
    let askQueue: AskCoordinator
    let knowledgeIndexer: KnowledgeIndexer
    let lock: AppLockController
    let system: SystemController
    let calendars: CalendarsModel
    let lockWindow: LockWindow
    let services: Services
    let modelManager: ModelManager
    let transcriptions: TranscriptionCoordinator
    private let reminders: any RemindersProvider
    private let speakerStore: any SpeakerStore
    private let speakerService: SpeakerService
    private let service: LibraryService
    private let transcriptStore: any TranscriptStore
    private let coordinatorForTranscripts: TranscriptionCoordinator
    /// iOS hands over background download events through the app delegate.
    let downloader: ModelDownloader?

    // The composition root is a long list of connections by nature, with no logic to extract.
    // swiftlint:disable:next function_body_length
    init() throws {
        let arguments = ProcessInfo.processInfo.arguments
        if Self.usesFakes, !arguments.contains("--show-setup") {
            UserDefaults.standard.set(true, forKey: "models.hasSeenSetup")
        }
        let services = try Self.usesFakes ? Services.fake() : Services.live()
        self.services = services
        store = services.store
        files = services.files
        let coordinator = RecordingCoordinator(
            engine: services.engine,
            store: services.store,
            files: services.files,
            assembler: services.assembler,
            activity: services.activity,
        )
        recorder = RecordingController(coordinator: coordinator, permission: services.permission, router: router)
        home = HomeModel(store: services.store, calendar: services.calendar, choices: services.calendarChoices)
        calendars = CalendarsModel(provider: services.calendar, choices: services.calendarChoices)
        service = LibraryService(store: services.store, files: services.files, audio: services.audio)
        library = LibraryController(service: service, store: services.store)

        transcriptStore = services.transcripts
        downloader = services.installer as? ModelDownloader
        let engines = services.engines
        let arbiter = ModelArbiter()
        var runners: [ModelRuntime: any ModelRunner] = engines.mapValues { $0 }
        runners[.fluidAudio] = services.diarizer
        runners[.mlx] = services.language
        runners[.appleLanguage] = services.embedder
        let allRunners = runners
        let manager = ModelManager(
            catalog: services.catalog,
            installer: services.installer,
            usage: services.usage,
            device: services.device,
            assets: services.assets,
            languageAssets: services.embeddingAssets,
            arbiter: arbiter,
            engines: { allRunners[$0] },
        )
        let catalog = services.catalog
        let installer = services.installer
        speakerStore = services.speakers
        let voiceModel: @Sendable () async -> ModelDescriptor? = {
            await manager.model(for: .speakerSeparation, language: nil)
        }
        speakerService = SpeakerService(store: services.speakers) { await voiceModel()?.id }
        people = PeopleModel(store: services.speakers, service: speakerService, recordings: services.store)
        let pipeline = SpeakerPipeline(
            store: services.speakers,
            transcripts: services.transcripts,
            engine: services.diarizer,
        ) {
            guard let model = await voiceModel() else { return nil }
            return (model, installer.folder(for: model.id))
        }
        let summaryQueue = Self.makeSummaryQueue(services: services, arbiter: arbiter, gate: gate)
        self.summaryQueue = summaryQueue
        let indexer = Self.makeIndexer(services: services, arbiter: arbiter, gate: gate)
        knowledgeIndexer = indexer
        let askQueue = Self.makeAskQueue(
            services: services, arbiter: arbiter, gate: gate, indexer: indexer, summaries: summaryQueue,
        )
        self.askQueue = askQueue
        ask = AskController(
            coordinator: askQueue, indexer: indexer, store: services.conversations, recordings: services.store,
            manager: manager,
        )
        reminders = services.reminders
        let summaryStore = services.summaries
        let notifier = services.notifier
        let gate = gate
        let transcriptions = TranscriptionCoordinator(
            store: services.transcripts,
            usage: services.usage,
            recordings: services.store,
            files: services.files,
            // UI tests have no audio on disk. A slow fake lets them see work in progress.
            source: Self.usesFakes && arguments.contains("--slow-transcription")
                ? FakeWindowSource(duration: 600) : SpeechWindowReader(),
            device: services.device,
            lease: services.lease,
            arbiter: arbiter,
            speakers: pipeline,
            vocabulary: { VocabularyPreferences.load() },
            onFinished: {
                await indexer.run()
                await Self.notifyTranscriptReady(notifier: notifier, gate: gate)
                await Self.summarizeIfWanted($0, queue: summaryQueue, manager: manager, store: summaryStore)
            },
            models: { id in
                catalog.models.first { $0.id == id }.map { ($0, installer.folder(for: id)) }
            },
            engines: { engines[$0] },
        )
        coordinatorForTranscripts = transcriptions
        self.transcriptions = transcriptions
        modelManager = manager
        transcription = TranscriptionCenter(coordinator: transcriptions, manager: manager)
        summaries = SummaryCenter(coordinator: summaryQueue, manager: manager, store: services.summaries)
        let store = services.store
        let files = services.files
        models = ModelsController(manager: manager, usage: services.usage, clip: {
            guard let url = Bundle.main.url(forResource: "speed-test", withExtension: "m4a") else { return nil }
            var windows = SpeechWindowReader().windows(of: url, from: 0).makeAsyncIterator()
            return try? await windows.next()
        }, trialRecordings: {
            let ready = await (try? store.recordings(status: .ready)) ?? []
            return ready.filter { $0.deletedAt == nil }.sorted { $0.createdAt > $1.createdAt }
        }, trialClip: { id in
            var windows = SpeechWindowReader().windows(of: files.audioFile(for: id), from: 0).makeAsyncIterator()
            return try? await windows.next()
        })

        lock = AppLockController(
            isEnabled: UserDefaults.standard.bool(forKey: AppLockPreferences.enabledKey),
            authenticator: services.authenticator,
            reason: L10n.System.lockReason,
        )
        lockWindow = LockWindow(controller: lock)
        system = SystemController(
            storage: services.storage, archiver: services.archiver, notifier: services.notifier,
        )
        let center = transcription
        recorder.onSaved = { id in
            let auto = UserDefaults.standard.string(forKey: AutoTranscribe.storageKey)
            if auto == AutoTranscribe.always.rawValue {
                Task { _ = await center.transcribe(id, language: nil) }
            }
        }

        let recorder = recorder
        connectSummaries(to: recorder, device: services.device)
        system.connect(
            pauseAllWork: { [weak self] in await self?.pauseAllWork() ?? false },
            resumeAllWork: { [weak self] in await self?.resumeAllWork() },
            eraseEverything: { [weak self] in try await self?.eraseEverything() },
        )
        RecordingCommandBridge.handler = { [weak self] in self?.handle($0) }
        recorder.recover()
        #if DEBUG
            // XCUITest cannot press the Action Button, so this enters where the button's intent enters.
            if arguments.contains("--press-action-button") {
                RecordingCommandBridge.send(.toggle)
            }
            if arguments.contains("--import-speed-clip"),
               let clip = Bundle.main.url(forResource: "speed-test", withExtension: "m4a")
            {
                library.importFiles([clip])
            }
        #endif
        #if DEBUG
            Self.startProbes(arguments: arguments, services: services, arbiter: arbiter)
        #endif
        // Killed only counts as a failure if the user was here. iOS ends background apps all the time.
        let wasActive = UserDefaults.standard.bool(forKey: Self.activeKey)
        Task { try? await transcriptions.resumeInterrupted(countKills: wasActive) }
    }

    private static let activeKey = "app.wasActive"

    /// Every step away from `.active` stops the model, not just `.background`. The GPU must be idle before iOS
    /// suspends the app, and by the time the background phase arrives that can be too late.
    func setActive(_ isActive: Bool) {
        UserDefaults.standard.set(isActive, forKey: Self.activeKey)
        gate.isForeground = isActive
        if !isActive {
            models.cancelSpeedTest()
        }
        let queue = summaryQueue
        let askQueue = askQueue
        let indexer = knowledgeIndexer
        let transcriptions = transcriptions
        Task {
            if isActive {
                await transcriptions.retryHeld()
                await queue.resume()
                await indexer.run()
            } else {
                // Fresh events, not Home's last load: a calendar may have been turned off since.
                await self.home.refreshEvents()
                await self.refreshWidgets()
                await self.scheduleReminders()
                await askQueue.stopAndRelease()
                await indexer.suspend()
                await queue.suspend()
            }
        }
    }

    /// Recordings that can be summarized, newest first.
    func transcribedRecordings() async -> [Recording] {
        let all = await (try? store.recordings(status: .ready)) ?? []
        var result: [Recording] = []
        for recording in all.sorted(by: { $0.createdAt > $1.createdAt }).prefix(30)
            where await (try? transcriptStore.transcript(for: recording.id))?.isComplete == true
        {
            result.append(recording)
        }
        return result
    }

    func detailModel(id: RecordingID, startTime: TimeInterval?) -> DetailModel {
        DetailModel(
            id: id, startTime: startTime, store: store, files: files, player: player,
            library: service, transcripts: transcriptStore, center: transcription,
            speakerStore: speakerStore, speakerService: speakerService,
            summaryCenter: summaries, reminders: reminders,
        )
    }

    private static var usesFakes: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("--fake-capture")
        #else
            false
        #endif
    }
}
