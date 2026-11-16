@testable import Domain
import Testing

struct AskWarmModelTests {
    @Test func `a follow-up reuses the loaded model, and the turn stays held meanwhile`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello"])
        let conversation = Conversation(scope: .recording(id), createdAt: .now)
        _ = await harness.ask("One", in: conversation)
        #expect(await harness.coordinator.holdsWarmModel)
        #expect(await !harness.arbiter.tryAcquire())
        _ = await harness.ask("Two", in: conversation)
        #expect(await harness.language.requests.count == 2)
        #expect(await harness.language.unloads == 0)
    }

    @Test func `leaving frees the warm model at once`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello"])
        _ = await harness.ask("One", scope: .recording(id))
        await harness.coordinator.stopAndRelease()
        #expect(await !harness.coordinator.holdsWarmModel)
        #expect(await harness.language.unloads == 1)
        #expect(await harness.arbiter.tryAcquire())
        #expect(harness.resumed.isOn)
    }

    @Test func `the warm model lets go by itself`() async throws {
        let harness = AskHarness(keepWarm: .milliseconds(20))
        let id = try await harness.addRecording(lines: ["Hello"])
        _ = await harness.ask("One", scope: .recording(id))
        var isFree = false
        for _ in 0 ..< 200 where !isFree {
            isFree = await harness.arbiter.tryAcquire()
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(isFree)
    }

    @Test func `the two kinds of model never sit in memory together`() async throws {
        let harness = AskHarness()
        try await harness.addRecording(lines: ["The zebra launch moved"])
        try await harness.index()
        let conversation = Conversation(scope: .library, createdAt: .now)
        _ = await harness.ask("zebra", in: conversation)
        _ = await harness.ask("zebra again", in: conversation)
        // The second search needs embeddings, so the warm language model leaves first.
        #expect(await harness.language.unloads >= 2)
    }

    @Test func `in a long meeting the citation lands on the phrase, not the start of the passage`() async throws {
        let harness = AskHarness()
        let lines = (0 ..< 200).map { index in
            index == 100 ? "Priya owns the zebra migration" : "Words about something ordinary, number \(index)."
        }
        let id = try await harness.addRecording(lines: lines)
        await harness.language.setAnswers(["Priya owns the zebra migration [1]."])

        let (message, _) = await harness.ask("Who owns the zebra migration?", scope: .recording(id))

        let citation = try #require(message?.citations.first)
        #expect(citation.time == 1000)
        #expect(citation.excerpt == "Priya owns the zebra migration")
    }
}
