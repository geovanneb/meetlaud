@testable import Domain
import Foundation
import Testing
import TestSupport

private let model = ModelDescriptor(id: "llm", displayName: "LLM", roles: [.chat], runtime: .mlx, languages: ["en"])
private let template = SummaryTemplate(
    name: "Test", category: .general, instructions: "Summarize.",
    sections: [TemplateSection(title: "Key points"), TemplateSection(title: "Tasks", kind: .tasks)],
)

private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    var isOpen: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

private struct Harness {
    let store = FakeSummaryStore()
    let transcripts = FakeTranscriptStore()
    let speakers = FakeSpeakerStore()
    let engine = ScriptedLanguageEngine()
    let arbiter = ModelArbiter()
    let gate = Gate(true)
    let coordinator: SummaryCoordinator
    let id = RecordingID()

    init() {
        let gate = gate
        coordinator = SummaryCoordinator(
            store: store, transcripts: transcripts, speakers: speakers, engine: engine, arbiter: arbiter,
            models: { $0 == "llm" ? (model, nil) : nil },
            canRun: { gate.isOpen },
        )
    }

    func addTranscript(lines: Int = 2) async throws {
        let segments = (0 ..< lines).map { index in
            TranscriptSegment(
                recordingID: id, start: Double(index), end: Double(index) + 1,
                text: "This is a sentence that Ana said in the meeting, number \(index), with some words.",
            )
        }
        try await transcripts.append(
            segments, job: TranscriptionJob(recordingID: id, modelID: "m", language: "en"),
        )
    }

    func finished() async throws {
        for _ in 0 ..< 500 {
            if await store.jobs.isEmpty {
                return
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("The queue did not finish")
    }
}

struct SummaryCoordinatorTests {
    @Test func `a short meeting skips the notes step, and goes straight to the model`() async throws {
        let harness = Harness()
        try await harness.addTranscript()
        try await harness.coordinator.enqueue(harness.id, template: template, modelID: "llm", language: "en")
        try await harness.finished()

        let requests = await harness.engine.requests
        #expect(requests.count == 2, "One request per section, and none for notes")
        #expect(requests[0].prompt.contains("number 1"), "The model sees the real transcript")
    }

    @Test func `a long meeting takes notes first`() async throws {
        let harness = Harness()
        try await harness.addTranscript(lines: 400)
        try await harness.coordinator.enqueue(harness.id, template: template, modelID: "llm", language: nil)
        try await harness.finished()

        let requests = await harness.engine.requests
        #expect(requests.filter { $0.system.contains("You take notes") }.count > 1)
        #expect(requests.last?.prompt.contains("A note from this part") == true)
    }

    @Test func `the summary holds validated items`() async throws {
        let harness = Harness()
        try await harness.addTranscript()
        try await harness.coordinator.enqueue(harness.id, template: template, modelID: "llm", language: "en")
        try await harness.finished()

        let summary = try #require(await harness.store.summaries(for: harness.id).first)
        #expect(summary.isComplete)
        let bullets = summary.sections[0].items
        #expect(bullets[0].sourceTime == 1)
        #expect(!bullets[0].needsReview)
        #expect(bullets[1].sourceTime == nil, "A citation to nothing must not survive")
        #expect(bullets[1].needsReview)

        let tasks = summary.sections[1].items
        #expect(tasks[0].owner == "Ana")
        #expect(tasks[1].needsReview, "An owner nobody mentioned must be flagged")
    }

    @Test func `sections appear as they finish`() async throws {
        let harness = Harness()
        try await harness.addTranscript()
        await harness.engine.setFailAfter(1)
        try await harness.coordinator.enqueue(harness.id, template: template, modelID: "llm", language: "en")
        try await harness.finished()
        let summary = await harness.store.summaries(for: harness.id).first
        #expect(summary?.sections.count == 1, "What finished stays, even when a later step fails")
    }

    @Test func `suspending stops and resuming continues from the same place`() async throws {
        let harness = Harness()
        try await harness.addTranscript()
        await harness.engine.setDelay(.milliseconds(30))
        try await harness.coordinator.enqueue(harness.id, template: template, modelID: "llm", language: "en")
        for _ in 0 ..< 200 where await harness.store.summaries(for: harness.id).first?.sections.isEmpty != false {
            try await Task.sleep(for: .milliseconds(2))
        }
        await harness.coordinator.suspend()
        let done = await harness.store.jobs.first?.nextSection
        #expect(done == 1)
        #expect(await harness.arbiter.tryAcquire(), "Suspending must free the model")
        await harness.arbiter.release()

        await harness.engine.setDelay(nil)
        await harness.coordinator.resume()
        try await harness.finished()
        let summary = await harness.store.summaries(for: harness.id).first
        #expect(summary?.sections.count == 2, "No section is written twice")
        #expect(summary?.isComplete == true)
    }

    @Test func `nothing runs while the app cannot use the GPU`() async throws {
        let harness = Harness()
        try await harness.addTranscript()
        harness.gate.isOpen = false
        let summaryID = try await harness.coordinator.enqueue(
            harness.id, template: template, modelID: "llm", language: "en",
        )
        try await Task.sleep(for: .milliseconds(30))
        #expect(await harness.engine.prepares == 0, "The model must not even load")
        #expect(await harness.coordinator.currentProgress[summaryID]?.phase == .waiting)

        harness.gate.isOpen = true
        await harness.coordinator.resume()
        try await harness.finished()
        #expect(await harness.store.summaries(for: harness.id).first?.isComplete == true)
    }

    @Test func `a summary waits for its turn with the model`() async throws {
        let harness = Harness()
        try await harness.addTranscript()
        await harness.arbiter.acquire()
        try await harness.coordinator.enqueue(harness.id, template: template, modelID: "llm", language: "en")
        try await Task.sleep(for: .milliseconds(30))
        #expect(await harness.engine.prepares == 0)
        await harness.arbiter.release()
        try await harness.finished()
    }

    @Test func `the model is released when the queue empties`() async throws {
        let harness = Harness()
        try await harness.addTranscript()
        try await harness.coordinator.enqueue(harness.id, template: template, modelID: "llm", language: "en")
        try await harness.finished()
        for _ in 0 ..< 200 where await harness.engine.unloads == 0 {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(await harness.engine.unloads == 1)
    }

    @Test func `a job that keeps killing the app stops being retried`() async throws {
        let harness = Harness()
        try await harness.addTranscript()
        let summary = Summary(
            recordingID: harness.id, templateName: "T", modelID: "llm", language: nil, createdAt: .now,
        )
        await harness.store.save(summary, job: SummaryJob(
            summaryID: summary.id, recordingID: harness.id, template: template, modelID: "llm", language: nil,
            attempts: SummaryCoordinator.Limits.attempts,
        ))
        await harness.coordinator.resume()
        try await harness.finished()
        #expect(await harness.engine.prepares == 0)
    }

    @Test func `stopping on purpose is not a failed attempt`() async throws {
        let harness = Harness()
        try await harness.addTranscript()
        await harness.engine.setDelay(.milliseconds(40))
        try await harness.coordinator.enqueue(harness.id, template: template, modelID: "llm", language: "en")
        for _ in 0 ..< 5 {
            await harness.coordinator.suspend()
            await harness.coordinator.resume()
        }
        await harness.coordinator.suspend()
        #expect(await harness.store.jobs.first?.attempts == 0)
    }

    @Test func `a resume that arrives while stopping is not lost`() async throws {
        let harness = Harness()
        try await harness.addTranscript()
        await harness.engine.setDelay(.milliseconds(5))
        try await harness.coordinator.enqueue(harness.id, template: template, modelID: "llm", language: "en")
        async let stop: Void = harness.coordinator.suspend()
        await harness.coordinator.resume()
        await stop
        await harness.coordinator.resume()
        try await harness.finished()
        #expect(await harness.store.summaries(for: harness.id).first?.isComplete == true)
    }

    @Test func `the model's language defaults to what was spoken`() async throws {
        let harness = Harness()
        try await harness.addTranscript()
        await harness.transcripts.save(Transcript(
            recordingID: harness.id,
            modelID: "m",
            language: "ja",
            isComplete: true,
        ))
        try await harness.coordinator.enqueue(harness.id, template: template, modelID: "llm", language: nil)
        try await harness.finished()
        #expect(await harness.engine.requests.first?.system.contains("code ja") == true)
    }

    @Test func `a recording with no transcript ends without touching the model`() async throws {
        let harness = Harness()
        try await harness.coordinator.enqueue(harness.id, template: template, modelID: "llm", language: nil)
        try await harness.finished()
        #expect(await harness.engine.prepares == 0)
    }

    @Test func `a missing model does not block the queue`() async throws {
        let harness = Harness()
        try await harness.addTranscript()
        try await harness.coordinator.enqueue(harness.id, template: template, modelID: "gone", language: nil)
        try await harness.coordinator.enqueue(harness.id, template: template, modelID: "llm", language: nil)
        try await harness.finished()
        let finished = await harness.store.summaries(for: harness.id).filter(\.isComplete)
        #expect(finished.count == 1)
    }

    @Test func `canceling something queued does not wait for the model`() async throws {
        let harness = Harness()
        try await harness.addTranscript()
        await harness.arbiter.acquire()
        let summaryID = try await harness.coordinator.enqueue(
            harness.id, template: template, modelID: "llm", language: nil,
        )
        try await harness.coordinator.cancel(summaryID)
        #expect(await harness.store.jobs.isEmpty)
        await harness.arbiter.release()
    }

    @Test func `canceling what is running stops it, and the queue continues`() async throws {
        let harness = Harness()
        try await harness.addTranscript()
        await harness.engine.setDelay(.milliseconds(30))
        let first = try await harness.coordinator.enqueue(harness.id, template: template, modelID: "llm", language: nil)
        try await harness.coordinator.enqueue(harness.id, template: template, modelID: "llm", language: nil)
        try await Task.sleep(for: .milliseconds(10))
        try await harness.coordinator.cancel(first)
        await harness.engine.setDelay(nil)
        try await harness.finished()
        let left = await harness.store.summaries(for: harness.id)
        #expect(left.count == 1)
        #expect(left.first?.id != first)
        #expect(left.first?.isComplete == true)
    }

    @Test func `a section that finishes during a stop is never written twice`() async throws {
        let harness = Harness()
        try await harness.addTranscript()
        await harness.engine.setDelay(.milliseconds(3))
        try await harness.coordinator.enqueue(harness.id, template: template, modelID: "llm", language: "en")
        for _ in 0 ..< 20 {
            await harness.coordinator.suspend()
            await harness.coordinator.resume()
            try await Task.sleep(for: .milliseconds(2))
        }
        await harness.engine.setDelay(nil)
        try await harness.finished()
        #expect(await harness.store.summaries(for: harness.id).first?.sections.count == 2)
    }

    @Test func `a template draft becomes an editable template`() async throws {
        let harness = Harness()
        let drafted = try await harness.coordinator.draftTemplate(
            description: "Sprint reviews", modelID: "llm", language: "en",
        )
        #expect(drafted.name == "Drafted")
        #expect(!drafted.isBuiltIn)
        #expect(await harness.arbiter.tryAcquire(), "The model must be free again")
        await harness.arbiter.release()
    }

    @Test func `canceling removes the unfinished summary`() async throws {
        let harness = Harness()
        try await harness.addTranscript()
        harness.gate.isOpen = false
        let summaryID = try await harness.coordinator.enqueue(
            harness.id, template: template, modelID: "llm", language: "en",
        )
        try await harness.coordinator.cancel(summaryID)
        #expect(await harness.store.all.isEmpty)
        #expect(await harness.store.jobs.isEmpty)
    }
}

struct SummaryWaitingTests {
    @Test func `suspending does not wait for another model to finish`() async throws {
        let harness = Harness()
        try await harness.addTranscript()
        await harness.arbiter.acquire()
        try await harness.coordinator.enqueue(harness.id, template: template, modelID: "llm", language: nil)
        try await Task.sleep(for: .milliseconds(50))

        // Holding the turn for this whole test: if suspending joined the line, it would never return.
        await harness.coordinator.suspend()

        #expect(await harness.engine.prepares == 0)
    }
}
