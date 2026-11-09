import Archive
import ASRApple
import ASRWhisperKit
import AudioCapture
import AudioEditing
import DeviceMonitoring
import DiarizationFluid
import Domain
import Embeddings
import Foundation
import LLMMLX
import ModelDelivery
import Persistence
import SystemBridges
import TestSupport

/// The outside world, real or scripted, in one place.
struct Services {
    let engine: any AudioCaptureEngine
    let assembler: any AudioAssembler
    let permission: any MicrophonePermission
    let activity: any RecordingActivityPresenter
    let store: any RecordingStore
    let files: any RecordingFiles
    let audio: any AudioProcessor
    let calendar: any CalendarProvider
    let catalog: any ModelCatalog
    let installer: any ModelInstaller
    let usage: any ModelUsageStore
    let transcripts: any TranscriptStore
    let device: any DeviceMonitor
    let assets: any SystemSpeechAssets
    let engines: [ModelRuntime: any TranscriptionEngine]
    let lease: any BackgroundWorkLease
    let speakers: any SpeakerStore
    let diarizer: any DiarizationEngine
    let language: any LanguageModelEngine
    let summaries: any SummaryStore
    let reminders: any RemindersProvider
    let conversations: any ConversationStore
    let knowledge: any KnowledgeStore
    let embedder: any TextEmbeddingEngine
    let embeddingAssets: any SystemSpeechAssets
    let authenticator: any DeviceAuthenticator
    let notifier: any LocalNotifier
    let storage: any StorageManaging
    let snapshots: any DatabaseSnapshots
    let archiver: any LibraryArchiver

    @MainActor
    static func live() throws -> Services {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true,
        )
        let files = try LocalRecordingFiles(root: support.appending(path: "Meetlaud"))
        let presenter = LiveActivityPresenter()
        Task { await presenter.endStale() }
        let database = try DatabaseStore(path: files.databasePath)
        try files.setBackupIncluded(UserDefaults.standard.bool(forKey: StoragePreferences.backupIncludedKey))
        let catalog = try BundledCatalog()
        let downloader = try ModelDownloader(
            root: support.appending(path: "Meetlaud/models"),
            catalog: catalog.models,
            freeBytes: { [files] in files.availableBytes() },
            log: { entry in Task { try? await database.logNetwork(entry) } },
        )
        return Services(
            engine: LiveCaptureEngine(),
            assembler: AACAssembler(),
            permission: LiveMicrophonePermission(),
            activity: presenter,
            store: database,
            files: files,
            audio: AssetAudioProcessor(),
            calendar: SystemCalendarProvider(),
            catalog: catalog,
            installer: downloader,
            usage: database,
            transcripts: database,
            device: SystemDeviceMonitor(storage: support),
            assets: AppleSpeechAssets(),
            engines: [.whisperKit: WhisperKitEngine(), .appleSpeech: AppleSpeechEngine()],
            lease: ContinuedProcessingLease(),
            speakers: database,
            diarizer: FluidDiarizationEngine(),
            language: MLXLanguageEngine(),
            summaries: database,
            reminders: SystemRemindersProvider(),
            conversations: database,
            knowledge: database,
            embedder: AppleTextEmbeddingEngine(),
            embeddingAssets: AppleEmbeddingAssets(),
            authenticator: SystemAuthenticator(),
            notifier: SystemNotifier(),
            storage: files,
            snapshots: database,
            archiver: LibraryArchive(root: files.root, snapshots: database),
        )
    }

    private static func seedTranscript(
        of recording: Recording,
        transcripts: FakeTranscriptStore,
        speakers: FakeSpeakerStore,
    ) async {
        let first = Speaker(recordingID: recording.id, number: 1, embedding: [1, 0], talkTime: 60)
        let second = Speaker(recordingID: recording.id, number: 2, embedding: [0, 1], talkTime: 4)
        let hello = TranscriptSegment(
            recordingID: recording.id, start: 0, end: 4, text: "Shall we start?", speaker: first.id.uuidString,
        )
        let reply = TranscriptSegment(
            recordingID: recording.id, start: 4, end: 8, text: "Yes, let us.", speaker: second.id.uuidString,
        )
        let job = TranscriptionJob(recordingID: recording.id, modelID: "fake-small", language: "en")
        try? await transcripts.append([hello, reply], job: job)
        await transcripts.deleteJob(for: recording.id)
        await transcripts.save(Transcript(
            recordingID: recording.id, modelID: "fake-small", language: "en", isComplete: true,
        ))
        await speakers.saveSpeakers([first, second], assignments: [:], for: recording.id)
    }

    private static func seed(
        _ store: InMemoryRecordingStore,
        transcripts: FakeTranscriptStore,
        speakers: FakeSpeakerStore,
    ) async {
        let now = Date()
        let folder = Folder(name: "Clients", createdAt: now)
        await store.insert(folder)
        let sales = Recording(title: "Sales meeting", createdAt: now, duration: 1920)
        await store.insert(sales)
        await store.insert(Recording(title: "Product memo", createdAt: now.addingTimeInterval(-3600), duration: 120))
        await store.insert(Recording(
            title: "Client call", createdAt: now.addingTimeInterval(-7200), duration: 600, folderID: folder.id,
        ))
        await store.insert(Recording(
            title: "Old draft", createdAt: now.addingTimeInterval(-9000), duration: 60, deletedAt: now,
        ))
        await store.insert(Marker(recordingID: sales.id, time: 75, kind: .note, text: "Pricing decision"))
        await seedTranscript(of: sales, transcripts: transcripts, speakers: speakers)
    }

    /// UI tests in the simulator have no microphone, so time passes with a scripted engine.
    /// A list of connections by nature, like the composition root.
    static func fake() -> Services { // swiftlint:disable:this function_body_length
        let engine = FakeCaptureEngine()
        Task {
            var recorded = 0.0
            while !Task.isCancelled {
                // Sleep throws only when cancelled, which ends the clock. The task cannot throw, so no error is lost.
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                recorded += 0.1
                engine.send(.progress(recorded: recorded, level: 0.5))
            }
        }
        let store = InMemoryRecordingStore()
        let transcripts = FakeTranscriptStore()
        let speakers = FakeSpeakerStore()
        let arguments = ProcessInfo.processInfo.arguments
        let hasLanguageModel = (arguments.contains("--seed-library") || arguments.contains("--showcase"))
            && !arguments.contains("--no-language-model")
        let summaries = FakeSummaryStore()
        let language = ScriptedLanguageEngine()
        let showcase = arguments.contains("--showcase")
        if showcase {
            Task { await language.setAnswers(ShowcaseSeed.answers) }
        }
        if showcase {
            Task { await ShowcaseSeed.seed(store, transcripts: transcripts, speakers: speakers, summaries: summaries) }
        } else if arguments.contains("--seed-library") {
            Task { await seed(store, transcripts: transcripts, speakers: speakers) }
        }
        return Services(
            engine: engine,
            assembler: FakeAssembler(),
            permission: FakeMicrophonePermission(),
            activity: FakeActivityPresenter(),
            store: store,
            files: FakeRecordingFiles(),
            audio: FakeAudioProcessor(),
            calendar: FakeCalendarProvider(events: [
                CalendarEvent(
                    id: "1", title: "Quarterly review", start: .now.addingTimeInterval(3600),
                    end: .now.addingTimeInterval(7200), attendees: ["Ana", "Bruno"],
                ),
            ]),
            catalog: FakeCatalog(),
            installer: FakeInstaller(installed: showcase
                ? ["fake-small", "fake-voices", "fake-chat", "fake-search"]
                : hasLanguageModel ? ["fake-voices", "fake-chat"] : ["fake-voices"]),
            usage: transcripts,
            transcripts: transcripts,
            device: FakeDeviceMonitor(condition: arguments.contains("--low-battery")
                ? DeviceCondition(isCharging: false, batteryLevel: 0.15)
                : DeviceCondition()),
            assets: FakeSpeechAssets(),
            engines: [.whisperKit: FakeTranscriptionEngine(
                delay: arguments.contains("--slow-transcription") ? .seconds(4) : .zero,
            )],
            lease: FakeLease(),
            speakers: speakers,
            diarizer: FakeDiarizationEngine(),
            language: language,
            summaries: summaries,
            reminders: FakeRemindersProvider(),
            conversations: FakeConversationStore(),
            knowledge: FakeKnowledgeStore(recordings: store),
            embedder: FakeEmbeddingEngine(),
            embeddingAssets: FakeSpeechAssets(),
            authenticator: FakeAuthenticator(delay: arguments.contains("--slow-unlock") ? .seconds(5) : .zero),
            notifier: FakeNotifier(),
            storage: FakeStorage(),
            snapshots: FakeDatabaseSnapshots(store: store),
            archiver: FakeArchiver(),
        )
    }
}

/// Whether a language model may run right now.
final class GenerationGate: @unchecked Sendable {
    // Unchecked because every property is guarded by the lock. Writes must happen in order on the main actor, so an
    // actor here would let a late write win.
    private let lock = NSLock()
    private var foreground = false
    private var recording = false

    var isForeground: Bool {
        get { lock.withLock { foreground } }
        set { lock.withLock { foreground = newValue } }
    }

    var isRecording: Bool {
        get { lock.withLock { recording } }
        set { lock.withLock { recording = newValue } }
    }

    var isOpen: Bool {
        lock.withLock { foreground && !recording }
    }
}
