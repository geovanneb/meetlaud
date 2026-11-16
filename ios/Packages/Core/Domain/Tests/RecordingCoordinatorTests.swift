@testable import Domain
import Foundation
import Testing
import TestSupport

private struct Boom: Error {}

private final class TestClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1000)
}

private struct Harness {
    let engine = FakeCaptureEngine()
    let store = InMemoryRecordingStore()
    let files = FakeRecordingFiles()
    let assembler = FakeAssembler()
    let activity = FakeActivityPresenter()
    let clock = TestClock()
    let coordinator: RecordingCoordinator

    init() {
        let clock = clock
        coordinator = RecordingCoordinator(
            engine: engine, store: store, files: files, assembler: assembler, activity: activity,
            now: { clock.date },
        )
    }

    /// Waits until the coordinator has processed what the fake engine sent.
    func settle(_ condition: @Sendable (RecordingSnapshot) -> Bool) async {
        for _ in 0 ..< 500 {
            if await condition(coordinator.currentSnapshot) {
                return
            }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Condition was not reached")
    }
}

struct RecordingCoordinatorTests {
    @Test func `start saves to the database before capture and marks it as capturing`() async throws {
        let harness = Harness()
        let id = try await harness.coordinator.start(title: "Sync")
        #expect(await harness.store.recording(id)?.status == .capturing)
        #expect(await harness.coordinator.currentSnapshot.status == .recording)
        #expect(await harness.activity.log == ["begin Sync"])
    }

    @Test func `a failed start leaves nothing behind`() async throws {
        let harness = Harness()
        harness.engine.startError = Boom()
        await #expect(throws: Boom.self) { try await harness.coordinator.start(title: "Sync") }
        #expect(await harness.store.all.isEmpty)
        #expect(await harness.coordinator.currentSnapshot.status == .idle)
    }

    @Test func `a second start is rejected`() async throws {
        let harness = Harness()
        try await harness.coordinator.start(title: "A")
        await #expect(throws: RecordingError.alreadyRecording) {
            try await harness.coordinator.start(title: "B")
        }
    }

    @Test func `stop saves, cleans segments, and releases the session`() async throws {
        let harness = Harness()
        let id = try await harness.coordinator.start(title: "Sync")
        let saved = try await harness.coordinator.stop()
        #expect(saved.status == .ready)
        #expect(saved.duration == 12)
        #expect(await harness.store.recording(id)?.status == .ready)
        #expect(!harness.files.hasSegments(for: id))
        #expect(harness.engine.calls == ["start", "stop", "deactivate"])
        #expect(await harness.coordinator.currentSnapshot.status == .idle)
    }

    @Test func `a failed save keeps the segments for recovery`() async throws {
        let harness = Harness()
        let id = try await harness.coordinator.start(title: "Sync")
        harness.assembler.error = Boom()
        await #expect(throws: Boom.self) { try await harness.coordinator.stop() }
        #expect(await harness.store.recording(id)?.status == .capturing)
        #expect(harness.files.hasSegments(for: id))
    }

    @Test func `pause and resume record the gap`() async throws {
        let harness = Harness()
        let id = try await harness.coordinator.start(title: "Sync")
        harness.engine.send(.progress(recorded: 10, level: 0.5))
        await harness.settle { $0.recorded == 10 }

        await harness.coordinator.pause()
        harness.clock.date.addTimeInterval(30)
        try await harness.coordinator.resume()

        let pauses = await harness.store.pauses(for: id)
        #expect(pauses == [PauseSpan(recordingID: id, position: 10, duration: 30, reason: .user)])
        #expect(await harness.coordinator.currentSnapshot.status == .recording)
    }

    @Test func `an interruption pauses and resumes by itself`() async throws {
        let harness = Harness()
        let id = try await harness.coordinator.start(title: "Sync")
        harness.engine.send(.interruptionBegan)
        await harness.settle { $0.status == .paused(.interruption) }

        harness.clock.date.addTimeInterval(60)
        harness.engine.send(.interruptionEnded(shouldResume: true))
        await harness.settle { $0.status == .recording }

        #expect(await harness.store.pauses(for: id).first?.reason == .interruption)
    }

    @Test func `the app resumes even when the system does not suggest it`() async throws {
        let harness = Harness()
        try await harness.coordinator.start(title: "Sync")
        harness.engine.send(.interruptionBegan)
        await harness.settle { $0.status == .paused(.interruption) }
        harness.engine.send(.interruptionEnded(shouldResume: false))
        await harness.settle { $0.status == .recording }
    }

    @Test func `when resuming fails the user can resume manually`() async throws {
        let harness = Harness()
        try await harness.coordinator.start(title: "Sync")
        harness.engine.resumeError = Boom()
        harness.engine.send(.interruptionBegan)
        await harness.settle { $0.status == .paused(.interruption) }
        harness.engine.send(.interruptionEnded(shouldResume: true))
        await harness.settle { $0.needsManualResume }

        harness.engine.resumeError = nil
        try await harness.coordinator.resume()
        let snapshot = await harness.coordinator.currentSnapshot
        #expect(snapshot.status == .recording)
        #expect(!snapshot.needsManualResume)
    }

    @Test func `an interruption does not override a user pause`() async throws {
        let harness = Harness()
        try await harness.coordinator.start(title: "Sync")
        await harness.coordinator.pause()
        harness.engine.send(.interruptionBegan)
        harness.engine.send(.interruptionEnded(shouldResume: true))
        try await Task.sleep(for: .milliseconds(50))
        #expect(await harness.coordinator.currentSnapshot.status == .paused(.user))
    }

    @Test func `stopping during an interruption saves the recording`() async throws {
        let harness = Harness()
        try await harness.coordinator.start(title: "Sync")
        harness.engine.send(.interruptionBegan)
        await harness.settle { $0.status == .paused(.interruption) }
        let saved = try await harness.coordinator.stop()
        #expect(saved.status == .ready)
    }

    @Test func `an engine failure keeps the audio and asks the user`() async throws {
        let harness = Harness()
        let id = try await harness.coordinator.start(title: "Sync")
        harness.engine.send(.failed("media services reset"))
        await harness.settle { $0.needsManualResume }
        #expect(await harness.store.recording(id)?.status == .capturing)
    }

    @Test func `markers use the audio position`() async throws {
        let harness = Harness()
        let id = try await harness.coordinator.start(title: "Sync")
        harness.engine.send(.progress(recorded: 42, level: 0.1))
        await harness.settle { $0.recorded == 42 }
        try await harness.coordinator.addMarker(kind: .note, text: "Call legal")
        #expect(await harness.store.markers(for: id).first?.time == 42)
        #expect(await harness.coordinator.currentSnapshot.markers.count == 1)
    }

    @Test func `low storage warns`() async throws {
        let harness = Harness()
        try await harness.coordinator.start(title: "Sync")
        harness.files.available = 400_000_000
        harness.engine.send(.progress(recorded: 10, level: 0))
        await harness.settle(\.isStorageLow)
    }

    @Test func `critical storage stops and saves`() async throws {
        let harness = Harness()
        let id = try await harness.coordinator.start(title: "Sync")
        harness.files.available = 50_000_000
        harness.engine.send(.progress(recorded: 10, level: 0))
        await harness.settle { $0.status == .idle }
        #expect(await harness.store.recording(id)?.status == .ready)
    }

    @Test func `recovery finishes a recording left by a crash`() async throws {
        let harness = Harness()
        let lost = Recording(title: "Lost", createdAt: .now, status: .capturing)
        await harness.store.insert(lost)
        harness.files.addSegments(for: lost.id)

        let recovered = try await harness.coordinator.recoverInterrupted()

        #expect(recovered.map(\.id) == [lost.id])
        let saved = await harness.store.recording(lost.id)
        #expect(saved?.status == .ready)
        #expect(saved?.wasRecovered == true)
        #expect(saved?.duration == 12)
    }

    @Test func `recovery removes a recording with no audio`() async throws {
        let harness = Harness()
        let empty = Recording(title: "Empty", createdAt: .now, status: .capturing)
        await harness.store.insert(empty)
        try await harness.coordinator.recoverInterrupted()
        #expect(await harness.store.recording(empty.id) == nil)
    }

    @Test func `recovery never touches the recording in progress`() async throws {
        let harness = Harness()
        let id = try await harness.coordinator.start(title: "Live")
        try await harness.coordinator.recoverInterrupted()
        #expect(await harness.store.recording(id)?.status == .capturing)
    }

    @Test func `failed recovery keeps the segments for a later try`() async throws {
        let harness = Harness()
        let lost = Recording(title: "Lost", createdAt: .now, status: .capturing)
        await harness.store.insert(lost)
        harness.files.addSegments(for: lost.id)
        harness.assembler.error = Boom()

        let recovered = try await harness.coordinator.recoverInterrupted()

        #expect(recovered.isEmpty)
        #expect(harness.files.hasSegments(for: lost.id))
        #expect(await harness.store.recording(lost.id)?.status == .capturing)
    }
}
