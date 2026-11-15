@testable import Domain
import Foundation
import Testing
import TestSupport

private let llm = ModelDescriptor(id: "llm", displayName: "LLM", roles: [.chat], runtime: .mlx, languages: ["en"])

final class AskFlag: @unchecked Sendable {
    // Unchecked because the lock guards every access.
    private let lock = NSLock()
    private var value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    var isOn: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

struct AskHarness {
    let conversations = FakeConversationStore()
    let recordings = InMemoryRecordingStore()
    let knowledge: FakeKnowledgeStore
    let transcripts = FakeTranscriptStore()
    let speakers = FakeSpeakerStore()
    let summaries = FakeSummaryStore()
    let language = ScriptedLanguageEngine()
    let embedder = FakeEmbeddingEngine()
    let arbiter = ModelArbiter()
    let canRun = AskFlag(true)
    let paused = AskFlag(false)
    let resumed = AskFlag(false)
    let indexer: KnowledgeIndexer
    let coordinator: AskCoordinator

    init(keepWarm: Duration = .seconds(60)) {
        let recordings = recordings
        let knowledge = FakeKnowledgeStore(recordings: recordings)
        self.knowledge = knowledge
        let canRun = canRun
        let paused = paused
        let resumed = resumed
        indexer = KnowledgeIndexer(
            recordings: recordings, transcripts: transcripts, speakers: speakers, knowledge: knowledge,
            engine: embedder, arbiter: arbiter, canRun: { canRun.isOn },
        )
        coordinator = AskCoordinator(
            conversations: conversations, knowledge: knowledge, recordings: recordings, transcripts: transcripts,
            speakers: speakers, summaries: summaries, language: language, embedder: embedder, indexer: indexer,
            arbiter: arbiter,
            models: { $0 == "llm" ? (llm, nil) : nil },
            canRun: { canRun.isOn },
            pauseOtherWork: { paused.isOn = true },
            resumeOtherWork: { resumed.isOn = true },
            keepWarm: keepWarm,
        )
    }

    @discardableResult
    func addRecording(
        _ title: String = "Sync",
        lines: [String],
        folder: FolderID? = nil,
        deleted: Bool = false,
        complete: Bool = true,
    ) async throws -> RecordingID {
        let recording = Recording(
            title: title, createdAt: .now, folderID: folder, deletedAt: deleted ? .now : nil,
        )
        await recordings.insert(recording)
        let segments = lines.enumerated().map { index, text in
            TranscriptSegment(
                recordingID: recording.id, start: Double(index) * 10, end: Double(index) * 10 + 5, text: text,
            )
        }
        try await transcripts.append(
            segments, job: TranscriptionJob(recordingID: recording.id, modelID: "m", language: "en"),
        )
        await transcripts.save(Transcript(
            recordingID: recording.id, modelID: "m", language: "en", isComplete: complete,
        ))
        return recording.id
    }

    func index() async throws {
        await indexer.run()
        for _ in 0 ..< 500 where await indexer.isRunning {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func ask(_ question: String, scope: AskScope, model: String? = "llm") async -> (ChatMessage?, [AskUpdate]) {
        let conversation = Conversation(scope: scope, createdAt: .now)
        return await ask(question, in: conversation, model: model)
    }

    func ask(_ question: String, in conversation: Conversation, model: String? = "llm") async
        -> (ChatMessage?, [AskUpdate])
    {
        var updates: [AskUpdate] = []
        var last: ChatMessage?
        for await update in await coordinator.ask(question, in: conversation, modelID: model) {
            updates.append(update)
            if case let .finished(message) = update {
                last = message
            }
        }
        return (last, updates)
    }
}

private func longMeeting(_ marker: String) -> [String] {
    (0 ..< 60).map { index in
        let filler = String(repeating: "several ordinary words about nothing much ", count: 8)
        return index == 40 ? marker : "\(filler) \(index)"
    }
}

struct AskCoordinatorTests {
    @Test func `a short meeting goes to the model whole, with a citation at the exact phrase`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello", "We move the launch to March"])
        await harness.language.setAnswers(["The launch moved to March [1]."])

        let (message, _) = await harness.ask("When is the launch?", scope: .recording(id))

        #expect(message?.state == .complete)
        #expect(message?.body == "The launch moved to March [1].")
        #expect(message?.citations.first?.time == 10)
        #expect(message?.citations.first?.excerpt == "We move the launch to March")
        #expect(message?.citations.first?.recordingID == id)
        let prompt = try #require(await harness.language.requests.first?.prompt)
        #expect(prompt.contains("[1] Hello We move the launch to March"))
    }

    @Test func `the question and the answer are both saved, and the chat gets a title`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello"])
        let conversation = Conversation(scope: .recording(id), createdAt: .now)

        _ = await harness.ask("What was said?", in: conversation)

        let saved = await harness.conversations.conversations()
        #expect(saved.first?.title == "What was said?")
        let messages = await harness.conversations.messages(in: conversation.id)
        #expect(messages.map(\.role) == [.user, .assistant])
    }

    @Test func `a long meeting that was never indexed can still be asked about`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: longMeeting("Priya owns the zebra migration"))
        await harness.language.setAnswers(["Priya [1]."])

        let (message, _) = await harness.ask("Who owns the zebra migration?", scope: .recording(id))

        #expect(message?.state == .complete)
        #expect(message?.citations.first?.excerpt.contains("zebra") == true)
    }

    @Test func `a broad question about a long meeting reads its summary, and the citation lands on the transcript`()
        async throws
    {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: longMeeting("We agreed to rebuild the onboarding flow"))
        await harness.summaries.save(Summary(
            recordingID: id, templateName: "Meeting", modelID: "llm", language: "en",
            sections: [SummarySection(title: "Topics", kind: .bullets, items: [
                SummaryItem(text: "Rebuilding the onboarding flow", sourceTime: 402),
                SummaryItem(text: "A point nobody said", sourceTime: 10, needsReview: true),
                SummaryItem(text: "A point with no moment"),
            ])],
            isComplete: true, createdAt: .now,
        ))
        await harness.language.setAnswers(["The meeting was about rebuilding the onboarding flow [1]."])

        let (message, _) = await harness.ask("What was the main topic?", scope: .recording(id))

        #expect(message?.state == .complete)
        #expect(message?.citations.first?.time == 400)
        #expect(message?.citations.first?.excerpt == "We agreed to rebuild the onboarding flow")
        let prompt = try #require(await harness.language.requests.first?.prompt)
        #expect(prompt.contains("[1] Summary, Topics: Rebuilding the onboarding flow"))
        #expect(!prompt.contains("A point nobody said"))
        #expect(!prompt.contains("A point with no moment"))
    }

    @Test func `the model decides there is no answer`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello"])
        await harness.language.setAnswers(["NOT_FOUND"])
        let (message, _) = await harness.ask("What is the capital of Australia?", scope: .recording(id))
        #expect(message?.state == .noBasis)
        #expect(message?.body.isEmpty == true)
    }

    @Test func `an answer with no citation is treated as no answer`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello"])
        await harness.language.setAnswers(["Canberra is the capital of Australia."])
        let (message, _) = await harness.ask("Capital?", scope: .recording(id))
        #expect(message?.state == .noBasis)
    }

    @Test func `with nothing in scope the model never loads`() async {
        let harness = AskHarness()
        let (message, _) = await harness.ask("Anything?", scope: .library)
        #expect(message?.state == .noBasis)
        #expect(await harness.language.prepares == 0)
    }

    @Test func `the library finds a meeting by a word it contains`() async throws {
        let harness = AskHarness()
        let wanted = try await harness.addRecording("Launch", lines: ["The zebra launch moved"])
        try await harness.addRecording("Other", lines: ["Nothing to see here at all"])
        try await harness.index()
        await harness.language.setAnswers(["Moved [1]."])

        let (message, _) = await harness.ask("What about the zebra launch?", scope: .library)

        #expect(message?.citations.first?.recordingID == wanted)
        #expect(message?.citations.first?.recordingTitle == "Launch")
    }

    @Test func `search still works when no embedding model covers the language`() async throws {
        let harness = AskHarness()
        await harness.embedder.setModel(nil)
        try await harness.addRecording(lines: ["The zebra launch moved"])
        try await harness.index()
        await harness.language.setAnswers(["Moved [1]."])
        let (message, _) = await harness.ask("zebra?", scope: .library)
        #expect(message?.state == .complete)
    }

    @Test func `the trash and other folders stay out of it`() async throws {
        let harness = AskHarness()
        let folder = FolderID()
        let inFolder = try await harness.addRecording("Inside", lines: ["zebra inside"], folder: folder)
        try await harness.addRecording("Outside", lines: ["zebra outside"])
        try await harness.addRecording("Trashed", lines: ["zebra trashed"], deleted: true)
        try await harness.index()

        let (message, _) = await harness.ask("zebra", scope: .folder(folder))

        #expect(message?.citations.map(\.recordingID) == [inFolder])
        let prompt = try #require(await harness.language.requests.first?.prompt)
        #expect(!prompt.contains("outside"))
        #expect(!prompt.contains("trashed"))
    }

    @Test func `a recording in the trash cannot be asked about`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Secret"], deleted: true)
        let (message, _) = await harness.ask("What?", scope: .recording(id))
        #expect(message?.state == .noBasis)
        #expect(await harness.language.requests.isEmpty)
    }

    @Test func `saving a memory needs no model, and later answers can use it`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello"])

        let (saved, _) = await harness.ask("Remember that Ana leads sales", scope: .recording(id), model: nil)
        #expect(saved?.state == .remembered)
        #expect(saved?.body == "Ana leads sales")
        #expect(await harness.language.prepares == 0)

        _ = await harness.ask("Who leads sales?", scope: .recording(id))
        let system = try #require(await harness.language.requests.first?.system)
        #expect(system.contains("Ana leads sales"))
    }

    @Test func `no model means a failed answer, and the question stays saved`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello"])
        let conversation = Conversation(scope: .recording(id), createdAt: .now)
        let (message, _) = await harness.ask("Hi", in: conversation, model: nil)
        #expect(message?.state == .failed)
        #expect(await harness.conversations.messages(in: conversation.id).first?.body == "Hi")
    }

    @Test func `the answer streams, and the refusal word never reaches the screen`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello"])
        await harness.language.setAnswers(["NOT_FOUND"])
        let (_, updates) = await harness.ask("Q", scope: .recording(id))
        #expect(updates.contains(.searching))
        #expect(!updates.contains { update in
            if case let .writing(text) = update {
                !text.isEmpty
            } else {
                false
            }
        })
    }

    @Test func `stopping keeps the question, gives the model back, and resumes other work`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello"])
        await harness.language.setDelay(.seconds(30))
        let conversation = Conversation(scope: .recording(id), createdAt: .now)
        let stream = await harness.coordinator.ask("Q", in: conversation, modelID: "llm")
        try await Task.sleep(for: .milliseconds(50))

        await harness.coordinator.stop()

        var last: AskUpdate?
        for await update in stream {
            last = update
        }
        guard case let .finished(message) = last else {
            Issue.record("No final message")
            return
        }
        #expect(message.state == .stopped)
        #expect(await harness.conversations.messages(in: conversation.id).count == 2)
        #expect(await harness.arbiter.tryAcquire())
        #expect(await harness.language.unloads == 1)
        #expect(await !harness.coordinator.holdsWarmModel)
        #expect(harness.paused.isOn)
        #expect(harness.resumed.isOn)
    }

    @Test func `a person can stop while another model holds the turn`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello"])
        await harness.arbiter.acquire()
        let stream = await harness.coordinator.ask(
            "Q", in: Conversation(scope: .recording(id), createdAt: .now), modelID: "llm",
        )
        try await Task.sleep(for: .milliseconds(50))
        await harness.coordinator.stop()
        var updates: [AskUpdate] = []
        for await update in stream {
            updates.append(update)
        }
        #expect(updates.contains(.waiting))
        #expect(await harness.language.prepares == 0)
        // It never had the turn, so it must not give it back.
        #expect(await !harness.arbiter.tryAcquire())
    }

    @Test func `conditions that forbid the model stop before it loads`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello"])
        harness.canRun.isOn = false
        let (message, _) = await harness.ask("Q", scope: .recording(id))
        #expect(message?.state == .stopped)
        #expect(await harness.language.prepares == 0)
    }

    @Test func `a model failure is reported and lets go of the turn`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello"])
        await harness.language.setFailAfter(0)
        let (message, _) = await harness.ask("Q", scope: .recording(id))
        #expect(message?.state == .failed)
        #expect(await harness.arbiter.tryAcquire())
    }

    @Test func `a follow-up sees the earlier turns and searches with them`() async throws {
        let harness = AskHarness()
        try await harness.addRecording(lines: ["The zebra launch moved"])
        try await harness.index()
        let conversation = Conversation(scope: .library, createdAt: .now)
        await harness.language.setAnswers(["Moved [1].", "Yes [1]."])
        _ = await harness.ask("What about zebra?", in: conversation)
        let (message, _) = await harness.ask("Why?", in: conversation)
        #expect(message?.state == .complete)
        let prompt = try #require(await harness.language.requests.last?.prompt)
        #expect(prompt.contains("Person: What about zebra?"))
    }
}
