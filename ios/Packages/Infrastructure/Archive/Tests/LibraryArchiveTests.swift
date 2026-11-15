@testable import Archive
import Domain
import Foundation
import GRDB
import Persistence
import Testing

private final class Workspace {
    let folder = FileManager.default.temporaryDirectory.appending(path: "archive-test-\(UUID().uuidString)")
    let store: DatabaseStore
    let files: LocalRecordingFiles
    let archive: LibraryArchive

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        files = try LocalRecordingFiles(root: folder)
        store = try DatabaseStore(path: files.databasePath)
        archive = LibraryArchive(root: folder, snapshots: store)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    func addRecording(_ title: String, audio: Data = Data("sound".utf8)) async throws -> Recording {
        let recording = Recording(title: title, createdAt: .now)
        try await store.insert(recording)
        try files.prepare(for: recording.id)
        try audio.write(to: files.audioFile(for: recording.id))
        return recording
    }

    func export(_ password: String = "correct horse", voicePrints: Bool = true) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).meetlaudbackup")
        try await archive.export(to: url, password: password, includingVoicePrints: voicePrints) { _ in }
        return url
    }
}

struct LibraryArchiveTests {
    @Test func `a library survives the trip to another device`() async throws {
        let old = try Workspace()
        let large = Data((0 ..< 3_500_000).map { UInt8($0 % 251) })
        let recording = try await old.addRecording("Sync", audio: large)
        let url = try await old.export()

        let new = try Workspace()
        _ = try await new.addRecording("Replaced")
        try await new.archive.restore(from: url, password: "correct horse") { _ in }

        #expect(try await new.store.recordings(status: .ready).map(\.title) == ["Sync"])
        #expect(try Data(contentsOf: new.files.audioFile(for: recording.id)) == large)
    }

    @Test func `the file holds no readable text`() async throws {
        let workspace = try Workspace()
        _ = try await workspace.addRecording("Confidential merger", audio: Data("secret-audio-bytes".utf8))
        let data = try await Data(contentsOf: workspace.export())
        #expect(data.range(of: Data("Confidential".utf8)) == nil)
        #expect(data.range(of: Data("secret-audio-bytes".utf8)) == nil)
        #expect(data.range(of: Data("SQLite".utf8)) == nil)
    }

    @Test func `a wrong password is named as such, and changes nothing`() async throws {
        let old = try Workspace()
        _ = try await old.addRecording("Sync")
        let url = try await old.export()
        let new = try Workspace()
        _ = try await new.addRecording("Mine")

        await #expect(throws: ArchiveError.wrongPassword) {
            try await new.archive.restore(from: url, password: "wrong") { _ in }
        }
        #expect(try await new.store.recordings(status: .ready).map(\.title) == ["Mine"])
    }

    @Test func `a cut file fails and changes nothing, even past the first block`() async throws {
        let old = try Workspace()
        _ = try await old.addRecording("Sync", audio: Data(repeating: 7, count: 3_000_000))
        let url = try await old.export()
        let data = try Data(contentsOf: url)
        try data.prefix(data.count - 1_500_000).write(to: url)

        let new = try Workspace()
        let mine = try await new.addRecording("Mine")
        await #expect(throws: ArchiveError.damaged) {
            try await new.archive.restore(from: url, password: "correct horse") { _ in }
        }
        #expect(try await new.store.recordings(status: .ready).map(\.id) == [mine.id])
        #expect(FileManager.default.fileExists(atPath: new.files.audioFile(for: mine.id).path))
    }

    @Test func `one changed byte is caught`() async throws {
        let old = try Workspace()
        _ = try await old.addRecording("Sync", audio: Data(repeating: 7, count: 2_500_000))
        let url = try await old.export()
        var data = try Data(contentsOf: url)
        data[data.count - 1000] ^= 0xFF
        try data.write(to: url)
        let new = try Workspace()
        await #expect(throws: ArchiveError.damaged) {
            try await new.archive.restore(from: url, password: "correct horse") { _ in }
        }
    }

    @Test func `trailing data cannot replace the existing library`() async throws {
        let old = try Workspace()
        _ = try await old.addRecording("Replacement")
        let url = try await old.export()
        defer { try? FileManager.default.removeItem(at: url) }
        let output = try FileHandle(forWritingTo: url)
        try output.seekToEnd()
        try output.write(contentsOf: Data([42]))
        try output.close()
        let new = try Workspace()
        let mine = try await new.addRecording("Original")
        await #expect(throws: ArchiveError.damaged) {
            try await new.archive.restore(from: url, password: "correct horse") { _ in }
        }
        #expect(try await new.store.recordings(status: .ready).map(\.id) == [mine.id])
        #expect(try Data(contentsOf: new.files.audioFile(for: mine.id)) == Data("sound".utf8))
    }

    @Test func `duplicate entries are rejected before restoring the database`() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try SealedWriter(url: url, password: "correct horse")
        let name = Data("database.sqlite".utf8)
        let entry = withUnsafeBytes(of: UInt32(name.count).bigEndian) { Data($0) }
            + name + Data(repeating: 0, count: 8)
        try writer.write(entry + entry + Data(repeating: 0, count: 4))
        try writer.finish()
        let workspace = try Workspace()
        let mine = try await workspace.addRecording("Original")
        await #expect(throws: ArchiveError.damaged) {
            try await workspace.archive.restore(from: url, password: "correct horse") { _ in }
        }
        #expect(try await workspace.store.recordings(status: .ready).map(\.id) == [mine.id])
    }

    @Test func `a file that is not an archive is refused`() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data("not an archive at all, just some text in a file".utf8).write(to: url)
        let new = try Workspace()
        await #expect(throws: ArchiveError.damaged) {
            try await new.archive.restore(from: url, password: "x") { _ in }
        }
    }

    @Test(arguments: [
        "../outside", "recordings/../../outside", "/etc/passwd", "recordings/a/./b", "other/file", "recordings//b", "",
        "recordings", "recordings/a\0/b",
    ])
    func `no path from a file can escape the folder`(name: String) {
        let folder = URL(filePath: "/tmp/work")
        #expect(throws: ArchiveError.damaged) { try LibraryArchive.destination(of: name, in: folder) }
    }

    @Test func `normal paths pass`() throws {
        let folder = URL(filePath: "/tmp/work")
        #expect(try LibraryArchive.destination(of: "recordings/a/audio/1.raw", in: folder).path
            == "/tmp/work/recordings/a/audio/1.raw")
    }

    @Test func `leaving voice prints out leaves out every voice`() async throws {
        let workspace = try Workspace()
        let recording = try await workspace.addRecording("Sync")
        let marker: [Float] = [0.125, 0.25, 0.5]
        let bytes = marker.withUnsafeBytes { Data($0) }
        let person = Person(name: "Ana", createdAt: .now)
        try await workspace.store.insert(person)
        try await workspace.store.save(VoicePrint(personID: person.id, modelID: "m", embedding: marker, talkTime: 1))
        try await workspace.store.saveSpeakers(
            [Speaker(recordingID: recording.id, number: 1, embedding: marker, talkTime: 1)],
            assignments: [:], for: recording.id,
        )

        let snapshot = workspace.folder.appending(path: "snapshot.sqlite")
        try await workspace.store.writeSnapshot(to: snapshot, includingVoicePrints: false)

        #expect(try Data(contentsOf: snapshot).range(of: bytes) == nil)
        let copy = try DatabaseQueue(path: snapshot.path)
        #expect(try await copy.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM voicePrint") } == 0)
        #expect(try await copy.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM recording") } == 1)
    }

    @Test func `erasing leaves every table empty`() async throws {
        let workspace = try Workspace()
        _ = try await workspace.addRecording("Sync")
        try await workspace.store.save(Conversation(scope: .library, createdAt: .now))
        try await workspace.store.save(MemoryItem(text: "Ana", createdAt: .now))
        try await workspace.store.logNetwork(NetworkLogEntry(host: "h", modelID: "m", bytes: 1, date: .now))

        try await workspace.store.eraseEverything()

        let queue = try DatabasePool(path: workspace.files.databasePath)
        let counts = try await queue.read { db in
            try String.fetchAll(db, sql: """
            SELECT name FROM sqlite_master WHERE type = 'table'
            AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%' AND name NOT LIKE '%Search%'
            """).map { try (name: $0, count: Int.fetchOne(db, sql: "SELECT count(*) FROM \($0)") ?? 0) }
        }
        #expect(counts.count > 15)
        #expect(counts.filter { $0.count > 0 }.isEmpty)
    }
}
