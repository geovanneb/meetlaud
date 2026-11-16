@testable import Domain
import Testing

struct KnowledgeIndexerTests {
    @Test func `it indexes finished transcripts only, and leaves the trash alone`() async throws {
        let harness = AskHarness()
        let ready = try await harness.addRecording(lines: ["Hello"])
        try await harness.addRecording(lines: ["Half"], complete: false)
        try await harness.addRecording(lines: ["Gone"], deleted: true)
        try await harness.index()
        #expect(await Array(harness.knowledge.chunksByRecording.keys) == [ready])
        #expect(await harness.knowledge.chunksByRecording[ready]?.first?.vector != nil)
    }

    @Test func `running again with no change does nothing`() async throws {
        let harness = AskHarness()
        try await harness.addRecording(lines: ["Hello"])
        try await harness.index()
        try await harness.index()
        #expect(await harness.knowledge.replacements == 1)
    }

    @Test func `an edit to the transcript rebuilds it`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello"])
        try await harness.index()
        var segment = try #require(await harness.transcripts.segments(for: id).first)
        segment.text = "Goodbye"
        await harness.transcripts.update(segment)
        try await harness.index()
        #expect(await harness.knowledge.chunksByRecording[id]?.first?.text == "Goodbye")
    }

    @Test func `a new model rebuilds, so that no vector stays behind on an old one`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello"])
        try await harness.index()
        await harness.embedder.setModel("newer")
        try await harness.index()
        #expect(await harness.knowledge.chunksByRecording[id]?.first?.modelID == "newer")
    }

    @Test func `a model arriving later upgrades text indexed without one`() async throws {
        let harness = AskHarness()
        await harness.embedder.setModel(nil)
        let id = try await harness.addRecording(lines: ["Hello"])
        try await harness.index()
        #expect(await harness.knowledge.chunksByRecording[id]?.first?.vector == nil)
        await harness.embedder.setModel("fake-embedding")
        try await harness.index()
        #expect(await harness.knowledge.chunksByRecording[id]?.first?.vector != nil)
    }

    @Test func `a removed transcript leaves nothing to find`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello"])
        try await harness.index()
        await harness.transcripts.deleteTranscript(for: id)
        try await harness.index()
        #expect(await harness.knowledge.chunksByRecording[id] == nil)
    }

    @Test func `it does not start when conditions forbid it, and gives the model back when it runs`() async throws {
        let harness = AskHarness()
        try await harness.addRecording(lines: ["Hello"])
        harness.canRun.isOn = false
        try await harness.index()
        #expect(await harness.knowledge.replacements == 0)
        harness.canRun.isOn = true
        try await harness.index()
        #expect(await harness.knowledge.replacements == 1)
        #expect(await harness.arbiter.tryAcquire())
    }

    @Test func `it waits for its turn, and stopping gets out of the wait`() async throws {
        let harness = AskHarness()
        try await harness.addRecording(lines: ["Hello"])
        await harness.arbiter.acquire()
        await harness.indexer.run()
        try await Task.sleep(for: .milliseconds(50))
        await harness.indexer.suspend()
        #expect(await harness.knowledge.replacements == 0)
        #expect(await !harness.indexer.isRunning)
    }
}
