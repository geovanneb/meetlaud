@testable import Domain
import Foundation
import Testing
import TestSupport

private struct Boom: Error {}

private final class TestClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_000_000)
}

private struct Harness {
    let store = InMemoryRecordingStore()
    let files = FakeRecordingFiles()
    let audio = FakeAudioProcessor()
    let clock = TestClock()
    let service: LibraryService

    init() {
        let clock = clock
        service = LibraryService(store: store, files: files, audio: audio, now: { clock.date })
    }

    func add(_ title: String, at time: TimeInterval = 100, duration: TimeInterval = 30) async -> Recording {
        let recording = Recording(title: title, createdAt: Date(timeIntervalSince1970: time), duration: duration)
        await store.insert(recording)
        return recording
    }
}

struct LibraryServiceTests {
    @Test func `rename trims and ignores blank names`() async throws {
        let harness = Harness()
        let recording = await harness.add("Old")
        try await harness.service.rename(recording.id, to: "  New  ")
        #expect(await harness.store.recording(recording.id)?.title == "New")
        try await harness.service.rename(recording.id, to: "   ")
        #expect(await harness.store.recording(recording.id)?.title == "New")
    }

    @Test func `moving and deleting a folder keeps its recordings`() async throws {
        let harness = Harness()
        let recording = await harness.add("Sync")
        let folder = try #require(try await harness.service.createFolder(named: "Clients"))
        try await harness.service.move([recording.id], to: folder.id)
        #expect(await harness.store.recording(recording.id)?.folderID == folder.id)

        try await harness.service.delete(folder)
        let kept = await harness.store.recording(recording.id)
        #expect(kept != nil)
        #expect(kept?.folderID == nil)
    }

    @Test func `a blank folder name creates nothing`() async throws {
        let harness = Harness()
        #expect(try await harness.service.createFolder(named: "  ") == nil)
    }

    @Test func `trash keeps the files and restore brings it back`() async throws {
        let harness = Harness()
        let recording = await harness.add("Sync")
        try await harness.service.trash([recording.id])
        #expect(await harness.store.recording(recording.id)?.deletedAt == harness.clock.date)
        #expect(!harness.files.wasRemoved(recording.id))

        try await harness.service.restore([recording.id])
        #expect(await harness.store.recording(recording.id)?.deletedAt == nil)
    }

    @Test func `delete forever removes the data and the files`() async throws {
        let harness = Harness()
        let recording = await harness.add("Sync")
        try await harness.service.deleteForever([recording.id])
        #expect(await harness.store.recording(recording.id) == nil)
        #expect(harness.files.wasRemoved(recording.id))
    }

    @Test func `only expired trash is purged`() async throws {
        let harness = Harness()
        let old = await harness.add("Old")
        let recent = await harness.add("Recent")
        try await harness.service.trash([old.id])
        harness.clock.date.addTimeInterval(LibraryService.trashRetention - 100)
        try await harness.service.trash([recent.id])
        harness.clock.date.addTimeInterval(200)

        #expect(try await harness.service.purgeExpiredTrash() == 1)
        #expect(await harness.store.recording(old.id) == nil)
        #expect(await harness.store.recording(recent.id) != nil)
    }

    @Test func `purging never touches recordings outside the trash`() async throws {
        let harness = Harness()
        let recording = await harness.add("Keep")
        harness.clock.date.addTimeInterval(LibraryService.trashRetention * 3)
        #expect(try await harness.service.purgeExpiredTrash() == 0)
        #expect(await harness.store.recording(recording.id) != nil)
    }

    @Test func `import creates a ready recording`() async throws {
        let harness = Harness()
        let source = URL(fileURLWithPath: "/tmp/memo.mp3")
        let recording = try await harness.service.importAudio(from: source, title: "memo")
        #expect(recording.status == .ready)
        #expect(recording.duration == 30)
        #expect(await harness.store.recording(recording.id) != nil)
    }

    @Test func `a failed import leaves nothing behind`() async throws {
        let harness = Harness()
        harness.audio.error = Boom()
        let source = URL(fileURLWithPath: "/tmp/memo.mp3")
        await #expect(throws: Boom.self) {
            try await harness.service.importAudio(from: source, title: "memo")
        }
        #expect(await harness.store.all.isEmpty)
    }

    @Test func `merge uses the earliest date, shifts markers, and trashes the originals`() async throws {
        let harness = Harness()
        let second = await harness.add("Second", at: 200, duration: 30)
        let first = await harness.add("First", at: 100, duration: 60)
        await harness.store.insert(Marker(recordingID: first.id, time: 10, kind: .flag))
        await harness.store.insert(Marker(
            recordingID: second.id, time: 5, kind: .photo, attachment: "a.jpg",
        ))

        let merged = try await harness.service.merge([second.id, first.id])

        #expect(merged.title == "First")
        #expect(merged.createdAt == first.createdAt)
        #expect(await harness.store.markers(for: merged.id).map(\.time) == [10, 65])
        #expect(harness.files.attachmentsCopied == 1)
        #expect(await harness.store.recording(first.id)?.deletedAt != nil)
        #expect(await harness.store.recording(second.id)?.deletedAt != nil)
    }

    @Test func `a failed merge leaves the originals alone`() async throws {
        let harness = Harness()
        let first = await harness.add("First", at: 100)
        let second = await harness.add("Second", at: 200)
        harness.audio.error = Boom()
        await #expect(throws: Boom.self) { try await harness.service.merge([first.id, second.id]) }
        #expect(await harness.store.recording(first.id)?.deletedAt == nil)
        #expect(await harness.store.all.count == 2)
    }

    @Test func `merging one recording is rejected`() async throws {
        let harness = Harness()
        let only = await harness.add("Only")
        await #expect(throws: LibraryError.nothingToMerge) { try await harness.service.merge([only.id]) }
    }
}

struct RecordingSortTests {
    private let recordings = [
        Recording(title: "b", createdAt: Date(timeIntervalSince1970: 2), duration: 5),
        Recording(title: "a", createdAt: Date(timeIntervalSince1970: 3), duration: 1),
        Recording(title: "C", createdAt: Date(timeIntervalSince1970: 1), duration: 9),
    ]

    @Test func `each order sorts as named`() {
        #expect(RecordingSort.newest.sorted(recordings).map(\.title) == ["a", "b", "C"])
        #expect(RecordingSort.oldest.sorted(recordings).map(\.title) == ["C", "b", "a"])
        #expect(RecordingSort.name.sorted(recordings).map(\.title) == ["a", "b", "C"])
        #expect(RecordingSort.longest.sorted(recordings).map(\.title) == ["C", "b", "a"])
    }
}
