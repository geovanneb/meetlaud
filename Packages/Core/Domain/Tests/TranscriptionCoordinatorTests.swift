@testable import Domain
import Foundation
import Testing
import TestSupport

private struct Harness {
    let store = FakeTranscriptStore()
    let recordings = InMemoryRecordingStore()
    let files = FakeRecordingFiles()
    let source: FakeWindowSource
    let device = FakeDeviceMonitor()
    let lease = FakeLease()
    let engine = FakeTranscriptionEngine()
    let arbiter = ModelArbiter()
    let coordinator: TranscriptionCoordinator
    let id = RecordingID()
    let model = ModelDescriptor(
        id: "m",
        displayName: "M",
        roles: [.transcription],
        runtime: .whisperKit,
        languages: ["en"],
    )

    init(duration: TimeInterval = 500) {
        source = FakeWindowSource(duration: duration)
        let engine = engine
        let model = model
        coordinator = TranscriptionCoordinator(
            store: store, usage: store, recordings: recordings, files: files, source: source,
            device: device, lease: lease, arbiter: arbiter,
            models: { $0 == "m" ? (model, nil) : nil },
            engines: { _ in engine },
        )
    }

    func finished() async {
        for _ in 0 ..< 500 {
            if await store.jobs().isEmpty {
                return
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("The queue did not finish")
    }
}

struct SpeakerStepTests {
    private func harness(
        engine: FakeDiarizationEngine,
        store: FakeSpeakerStore,
        hasModel: Bool = true,
    ) -> (Harness, TranscriptionCoordinator) {
        let harness = Harness()
        let model = harness.model
        let fake = harness.engine
        let pipeline = SpeakerPipeline(
            store: store, transcripts: harness.store, engine: engine,
            model: { hasModel ? (model, nil) : nil },
        )
        let coordinator = TranscriptionCoordinator(
            store: harness.store, usage: harness.store, recordings: harness.recordings, files: harness.files,
            source: harness.source, device: harness.device, lease: harness.lease, arbiter: harness.arbiter,
            speakers: pipeline,
            models: { $0 == "m" ? (model, nil) : nil },
            engines: { _ in fake },
        )
        return (harness, coordinator)
    }

    @Test func `speakers come right after the text, before the job ends`() async throws {
        let engine = FakeDiarizationEngine(turns: [
            SpeakerTurn(speaker: "A", start: 0, end: 500, embedding: [1, 0]),
        ])
        let speakers = FakeSpeakerStore()
        let (harness, coordinator) = harness(engine: engine, store: speakers)
        try await coordinator.enqueue(harness.id, modelID: "m", language: "en")
        await harness.finished()
        #expect(await speakers.speakers(for: harness.id).count == 1)
        #expect(await harness.engine.unloads >= 1, "The speech model must be gone before diarization starts")
    }

    @Test func `a diarization failure never costs the transcript`() async throws {
        let engine = FakeDiarizationEngine()
        await engine.setError(CocoaError(.fileReadCorruptFile))
        let (harness, coordinator) = harness(engine: engine, store: FakeSpeakerStore())
        try await coordinator.enqueue(harness.id, modelID: "m", language: "en")
        await harness.finished()
        #expect(await harness.store.transcript(for: harness.id)?.isComplete == true)
        #expect(await harness.store.segments(for: harness.id).count == 3)
    }

    @Test func `voices can be separated again with the count the person knows`() async throws {
        let engine = FakeDiarizationEngine(turns: [
            SpeakerTurn(speaker: "A", start: 0, end: 250, embedding: [1, 0]),
            SpeakerTurn(speaker: "B", start: 250, end: 500, embedding: [0, 1]),
        ])
        let speakers = FakeSpeakerStore()
        let (harness, coordinator) = harness(engine: engine, store: speakers)
        try await coordinator.enqueue(harness.id, modelID: "m", language: "en")
        await harness.finished()
        try await coordinator.redetectSpeakers(harness.id, count: .exactly(2))
        #expect(await engine.requested == [.automatic, .exactly(2)])
        #expect(await speakers.speakers(for: harness.id).count == 2)
        #expect(await coordinator.currentProgress[harness.id] == nil)
        #expect(await harness.arbiter.tryAcquire(), "The model is free again afterwards")
    }

    @Test func `with no speaker model, the transcript finishes without speakers`() async throws {
        let speakers = FakeSpeakerStore()
        let (harness, coordinator) = harness(
            engine: FakeDiarizationEngine(), store: speakers, hasModel: false,
        )
        try await coordinator.enqueue(harness.id, modelID: "m", language: "en")
        await harness.finished()
        #expect(await harness.store.transcript(for: harness.id)?.isComplete == true)
        #expect(await speakers.all.isEmpty)
    }
}

struct TranscriptionCoordinatorTests {
    @Test func `transcribing again keeps the text it replaces`() async throws {
        let harness = Harness()
        try await harness.coordinator.enqueue(harness.id, modelID: "m", language: nil)
        await harness.finished()
        let first = await harness.store.segments(for: harness.id).map(\.text)

        try await harness.coordinator.enqueue(harness.id, modelID: "m", language: nil)
        await harness.finished()

        let versions = await harness.store.versions(for: harness.id)
        #expect(versions.count == 1)
        #expect(versions.first?.segments.map(\.text) == first)
    }

    @Test func `a first transcript leaves no empty version behind`() async throws {
        let harness = Harness()
        try await harness.coordinator.enqueue(harness.id, modelID: "m", language: nil)
        await harness.finished()
        #expect(await harness.store.versions(for: harness.id).isEmpty)
    }

    @Test func `restoring swaps the two, so it can be undone`() async throws {
        let harness = Harness()
        let old = TranscriptVersion(
            recordingID: harness.id, modelID: "old", language: "en", savedAt: .now,
            segments: [TranscriptSegment(recordingID: harness.id, start: 1, end: 2, text: "Earlier words")],
        )
        try await harness.coordinator.enqueue(harness.id, modelID: "m", language: nil)
        await harness.finished()
        await harness.store.save(old)

        try await harness.coordinator.restore(old)

        #expect(await harness.store.segments(for: harness.id).map(\.text) == ["Earlier words"])
        #expect(await harness.store.transcript(for: harness.id)?.modelID == "old")
        #expect(await harness.store.transcript(for: harness.id)?.isComplete == true)
        let kept = await harness.store.versions(for: harness.id)
        #expect(kept.count == 1)
        #expect(kept.first?.modelID == "m")
        #expect(await harness.store.job(for: harness.id) == nil, "A restored transcript is not a running job")
    }

    @Test func `a job saves every window and finishes`() async throws {
        let harness = Harness()
        try await harness.coordinator.enqueue(harness.id, modelID: "m", language: nil)
        await harness.finished()

        let segments = await harness.store.segments(for: harness.id)
        #expect(segments.map(\.start) == [1, 181, 361])
        #expect(segments.first?.text == "Text at 0", "Text is trimmed, and blank segments are dropped")
        let transcript = await harness.store.transcript(for: harness.id)
        #expect(transcript?.isComplete == true)
        #expect(transcript?.language == "pt", "Detected language is kept")
    }

    @Test func `finishing records real speed`() async throws {
        let harness = Harness()
        try await harness.coordinator.enqueue(harness.id, modelID: "m", language: "en")
        await harness.finished()
        for _ in 0 ..< 100 where await harness.store.allStats.isEmpty {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(await harness.store.allStats.first?.audioDuration == 500)
    }

    @Test func `the engine is released when the queue empties`() async throws {
        let harness = Harness()
        try await harness.coordinator.enqueue(harness.id, modelID: "m", language: "en")
        await harness.finished()
        for _ in 0 ..< 200 where await harness.engine.unloads == 0 {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(await harness.engine.unloads == 1)
    }

    @Test func `a job interrupted by iOS resumes from its checkpoint and counts as a kill`() async throws {
        let harness = Harness()
        await harness.store.save(TranscriptionJob(
            recordingID: harness.id, modelID: "m", language: "en", checkpoint: 180, state: .running,
        ))
        try await harness.coordinator.resumeInterrupted()
        await harness.finished()

        #expect(harness.source.requestedStarts == [180])
        #expect(await harness.store.segments(for: harness.id).first?.start == 181)
        #expect(await harness.store.allStats.contains { $0.outcome == .killed })
    }

    @Test func `a failure mid-way keeps what was saved`() async throws {
        let harness = Harness()
        await harness.engine.setFailAfter(1)
        try await harness.coordinator.enqueue(harness.id, modelID: "m", language: "en")
        for _ in 0 ..< 200 where await harness.store.segments(for: harness.id).isEmpty {
            try await Task.sleep(for: .milliseconds(2))
        }
        try await Task.sleep(for: .milliseconds(30))
        #expect(await harness.store.segments(for: harness.id).count == 1)
        #expect(await harness.store.job(for: harness.id)?.checkpoint == 180)
    }

    @Test func `critical heat pauses between windows and cooling resumes alone`() async throws {
        let harness = Harness()
        harness.device.setCondition(DeviceCondition(thermal: .critical))
        try await harness.coordinator.enqueue(harness.id, modelID: "m", language: "en")
        for _ in 0 ..< 200 where await harness.store.job(for: harness.id)?.state != .paused {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(await harness.store.job(for: harness.id)?.state == .paused)
        #expect(await harness.engine.windows.isEmpty)
        #expect(await harness.coordinator.currentProgress[harness.id]?.phase == .waitingForDevice)

        harness.device.setCondition(DeviceCondition(thermal: .nominal))
        await harness.finished()
        #expect(await harness.store.transcript(for: harness.id)?.isComplete == true)
    }

    @Test func `a job for the charger waits until the device is plugged in`() async throws {
        let harness = Harness()
        harness.device.setCondition(DeviceCondition(isCharging: false, batteryLevel: 0.8))
        try await harness.coordinator.enqueue(harness.id, modelID: "m", language: "en", whenCharging: true)
        try await Task.sleep(for: .milliseconds(30))
        #expect(await harness.engine.windows.isEmpty)
        #expect(await harness.store.job(for: harness.id)?.state == .waitingForPower)
        #expect(await harness.coordinator.currentProgress[harness.id]?.phase == .waitingForPower)

        harness.device.setCondition(DeviceCondition(isCharging: true))
        await harness.finished()
        #expect(await harness.store.transcript(for: harness.id)?.isComplete == true)
    }

    @Test func `a job for the charger starts at once when already charging`() async throws {
        let harness = Harness()
        try await harness.coordinator.enqueue(harness.id, modelID: "m", language: "en", whenCharging: true)
        await harness.finished()
        #expect(await harness.store.transcript(for: harness.id)?.isComplete == true)
    }

    @Test func `a charging device that is hot still holds the job`() async throws {
        let harness = Harness()
        harness.device.setCondition(DeviceCondition(thermal: .serious, isCharging: true))
        try await harness.coordinator.enqueue(harness.id, modelID: "m", language: "en", whenCharging: true)
        try await Task.sleep(for: .milliseconds(30))
        #expect(await harness.engine.windows.isEmpty)
        #expect(await harness.store.job(for: harness.id)?.state == .waitingForPower)
    }

    @Test func `a job waits for its turn with the model`() async throws {
        let harness = Harness()
        await harness.arbiter.acquire()
        try await harness.coordinator.enqueue(harness.id, modelID: "m", language: "en")
        try await Task.sleep(for: .milliseconds(30))
        #expect(await harness.engine.windows.isEmpty, "Something else holds the model")

        await harness.arbiter.release()
        await harness.finished()
        #expect(await harness.store.transcript(for: harness.id)?.isComplete == true)
    }

    @Test func `the model is free again after the queue empties`() async throws {
        let harness = Harness()
        try await harness.coordinator.enqueue(harness.id, modelID: "m", language: "en")
        await harness.finished()
        var isFree = false
        for _ in 0 ..< 500 where !isFree {
            isFree = await harness.arbiter.tryAcquire()
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(isFree)
    }

    @Test func `canceling stops the job`() async throws {
        let harness = Harness(duration: 100_000)
        try await harness.coordinator.enqueue(harness.id, modelID: "m", language: "en")
        try await harness.coordinator.cancel(harness.id)
        await harness.finished()
        #expect(await harness.coordinator.currentProgress[harness.id] == nil)
    }

    @Test func `a model that is gone drops the job instead of looping`() async throws {
        let harness = Harness()
        try await harness.coordinator.enqueue(harness.id, modelID: "deleted", language: "en")
        await harness.finished()
        #expect(await harness.store.segments(for: harness.id).isEmpty)
    }

    @Test func `starting over replaces the earlier transcript`() async throws {
        let harness = Harness()
        try await harness.coordinator.enqueue(harness.id, modelID: "m", language: "en")
        await harness.finished()
        try await harness.coordinator.enqueue(harness.id, modelID: "m", language: "en")
        await harness.finished()
        #expect(await harness.store.segments(for: harness.id).count == 3)
    }
}
