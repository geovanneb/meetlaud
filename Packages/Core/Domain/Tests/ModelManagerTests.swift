@testable import Domain
import Foundation
import Testing
import TestSupport

private struct Harness {
    let usage = FakeTranscriptStore()
    let installer = FakeInstaller()
    let device = FakeDeviceMonitor()
    let engine = FakeTranscriptionEngine()
    let arbiter = ModelArbiter()
    let manager: ModelManager

    init() {
        let engine = engine
        let defaults = UserDefaults(suiteName: UUID().uuidString) ?? .standard
        manager = ModelManager(
            catalog: FakeCatalog(),
            installer: installer,
            usage: usage,
            device: device,
            assets: FakeSpeechAssets(),
            arbiter: arbiter,
            defaults: defaults,
            engines: { _ in engine },
        )
    }
}

struct ModelManagerTests {
    private let clip = AudioWindow(start: 0, end: 30, samples: [])

    /// The crash this prevents: a speed test finishing and unloading the model under a running transcription.
    @Test func `a speed test refuses to run while a model is in use`() async throws {
        let harness = Harness()
        await harness.arbiter.acquire()
        await #expect(throws: ModelArbiterError.busy) {
            try await harness.manager.runSpeedTest("fake-small", clip: clip, passes: 1)
        }
        #expect(await harness.engine.unloads == 0, "It must not touch the engine")
        #expect(await harness.engine.prepared.isEmpty)
    }

    @Test func `a speed test records the speed and frees the model`() async throws {
        let harness = Harness()
        let stat = try await harness.manager.runSpeedTest("fake-small", clip: clip, passes: 2)
        #expect(stat.audioDuration == 60)
        #expect(await harness.usage.allStats.count == 1)
        #expect(await harness.arbiter.tryAcquire(), "The model must be free afterwards")
    }

    @Test func `trying models frees the model, and a busy device refuses`() async throws {
        let harness = Harness()
        let clip = AudioWindow(start: 0, end: 60, samples: [])
        let trials = try await harness.manager.tryModels(["fake-small"], on: clip)
        #expect(trials.map(\.modelID) == ["fake-small"])
        #expect(await harness.engine.unloads == 1)
        #expect(await harness.arbiter.tryAcquire(), "The model must be free afterward")
        await #expect(throws: ModelArbiterError.busy) {
            try await harness.manager.tryModels(["fake-small"], on: clip)
        }
    }

    @Test func `a failed speed test frees the model too`() async throws {
        let harness = Harness()
        await harness.engine.setFailAfter(0)
        await #expect(throws: (any Error).self) {
            try await harness.manager.runSpeedTest("fake-small", clip: clip, passes: 1)
        }
        #expect(await harness.arbiter.tryAcquire())
    }

    @Test func `a language test measures speed and frees the model`() async throws {
        let language = ScriptedLanguageEngine()
        let arbiter = ModelArbiter()
        let manager = ModelManager(
            catalog: FakeCatalog(), installer: FakeInstaller(), usage: FakeTranscriptStore(),
            device: FakeDeviceMonitor(),
            assets: FakeSpeechAssets(), arbiter: arbiter,
            defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard,
            engines: { _ in language },
        )
        let speed = try await manager.runLanguageTest("fake-chat")
        #expect(speed.modelID == "fake-chat")
        #expect(speed.tokensPerSecond > 0)
        #expect(await language.unloads == 1)
        for _ in 0 ..< 100 where await !arbiter.tryAcquire() {
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    @Test func `a language test refuses to run while a model is in use`() async throws {
        let language = ScriptedLanguageEngine()
        let arbiter = ModelArbiter()
        await arbiter.acquire()
        let manager = ModelManager(
            catalog: FakeCatalog(), installer: FakeInstaller(), usage: FakeTranscriptStore(),
            device: FakeDeviceMonitor(),
            assets: FakeSpeechAssets(), arbiter: arbiter,
            defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard,
            engines: { _ in language },
        )
        await #expect(throws: ModelArbiterError.busy) { try await manager.runLanguageTest("fake-chat") }
        #expect(await language.prepares == 0)
    }

    @Test func `speed reads as a round number of words`() {
        #expect(LanguageSpeed(modelID: "m", tokensPerSecond: 36, firstTokenSeconds: 1).wordsPerMinute == 1620)
    }

    @Test func `a pinned model wins over the automatic choice`() async throws {
        let harness = Harness()
        for model in FakeCatalog().models {
            await harness.installer.install(model, allowsCellular: false)
        }
        try await harness.manager.select(.pinned("fake-small"), for: .transcription)
        #expect(await harness.manager.model(for: .transcription, language: "en")?.id == "fake-small")
    }

    @Test func `removing a model resets its pin`() async throws {
        let harness = Harness()
        await harness.installer.install(FakeCatalog().models[0], allowsCellular: false)
        try await harness.manager.select(.pinned("fake-small"), for: .transcription)
        try await harness.manager.remove("fake-small")
        #expect(await harness.usage.selection(for: .transcription) == .automatic)
    }

    @Test func `with no installed model there is nothing to use`() async {
        let harness = Harness()
        #expect(await harness.manager.model(for: .transcription, language: "en") == nil)
    }
}

struct ModelArbiterTests {
    @Test func `only one holder at a time`() async {
        let arbiter = ModelArbiter()
        #expect(await arbiter.tryAcquire())
        #expect(await arbiter.tryAcquire() == false)
        await arbiter.release()
        #expect(await arbiter.tryAcquire())
    }

    @Test func `release wakes the next in line`() async {
        let arbiter = ModelArbiter()
        await arbiter.acquire()
        let waiter = Task {
            await arbiter.acquire()
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
        await arbiter.release()
        #expect(await waiter.value)
        #expect(await arbiter.tryAcquire() == false, "The turn passed on, so it stays held")
    }
}
