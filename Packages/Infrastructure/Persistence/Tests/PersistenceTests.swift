import Domain
import Foundation
import GRDB
@testable import Persistence
import Testing

struct DatabaseStoreTests {
    private func store() throws -> DatabaseStore {
        try DatabaseStore(database: DatabaseQueue())
    }

    @Test func `a recording round-trips`() async throws {
        let store = try store()
        let recording = Recording(
            title: "Sync", createdAt: Date(timeIntervalSince1970: 1000), duration: 5, status: .capturing,
        )
        try await store.insert(recording)
        #expect(try await store.recording(recording.id) == recording)
    }

    @Test func `filtering by status finds interrupted recordings`() async throws {
        let store = try store()
        let open = Recording(title: "Open", createdAt: .now, status: .capturing)
        try await store.insert(open)
        try await store.insert(Recording(title: "Done", createdAt: .now, status: .ready))
        #expect(try await store.recordings(status: .capturing).map(\.id) == [open.id])
    }

    @Test func `markers come back in time order`() async throws {
        let store = try store()
        let recording = Recording(title: "Sync", createdAt: .now)
        try await store.insert(recording)
        try await store.insert(Marker(recordingID: recording.id, time: 30, kind: .flag))
        try await store.insert(Marker(recordingID: recording.id, time: 10, kind: .note, text: "Hi"))
        #expect(try await store.markers(for: recording.id).map(\.time) == [10, 30])
    }

    @Test func `deleting a recording removes its markers and pauses`() async throws {
        let store = try store()
        let recording = Recording(title: "Sync", createdAt: .now)
        try await store.insert(recording)
        try await store.insert(Marker(recordingID: recording.id, time: 1, kind: .flag))
        try await store.insert(PauseSpan(recordingID: recording.id, position: 1, duration: 2, reason: .user))
        try await store.delete(recording.id)
        #expect(try await store.markers(for: recording.id).isEmpty)
        #expect(try await store.pauses(for: recording.id).isEmpty)
    }

    @Test func `observers see changes, newest first`() async throws {
        let store = try store()
        var iterator = store.observeRecordings().makeAsyncIterator()
        #expect(await iterator.next()?.isEmpty == true)
        let older = Recording(title: "Old", createdAt: Date(timeIntervalSince1970: 1))
        try await store.insert(older)
        #expect(await iterator.next()?.map(\.title) == ["Old"])
        try await store.insert(Recording(title: "New", createdAt: Date(timeIntervalSince1970: 2)))
        #expect(await iterator.next()?.map(\.title) == ["New", "Old"])
    }
}

struct LocalRecordingFilesTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    @Test func `the root is excluded from backup`() throws {
        _ = try LocalRecordingFiles(root: root)
        let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func `segments are detected only when they hold audio`() throws {
        let files = try LocalRecordingFiles(root: root)
        let id = RecordingID()
        let directory = try files.segmentsDirectory(for: id)
        #expect(!files.hasSegments(for: id))
        try Data().write(to: directory.appending(path: "part-000001.pcm"))
        #expect(!files.hasSegments(for: id))
        try Data([1, 2, 3, 4]).write(to: directory.appending(path: "part-000002.pcm"))
        #expect(files.hasSegments(for: id))
    }

    @Test func `removing segments keeps the final audio`() throws {
        let files = try LocalRecordingFiles(root: root)
        let id = RecordingID()
        let directory = try files.segmentsDirectory(for: id)
        try Data([1]).write(to: directory.appending(path: "part-000001.pcm"))
        try Data([2]).write(to: files.audioFile(for: id))
        try files.removeSegments(for: id)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(FileManager.default.fileExists(atPath: files.audioFile(for: id).path))
    }
}

struct LibraryPersistenceTests {
    private func store() throws -> DatabaseStore {
        try DatabaseStore(database: DatabaseQueue())
    }

    /// Real phones hold v1 data. A migration that loses it would be the worst bug this app could ship.
    @Test func `v1 data survives the migration to the library schema`() async throws {
        let queue = try DatabaseQueue()
        let id = UUID().uuidString
        var migrator = DatabaseStore.migrator
        migrator.eraseDatabaseOnSchemaChange = false
        try migrator.migrate(queue, upTo: "v1")
        try await queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO recording (id, title, createdAt, duration, status, wasRecovered)
                VALUES (?, 'Old meeting', '2026-11-06 10:00:00.000', 120, 'ready', 0)
                """,
                arguments: [id],
            )
        }

        let store = try DatabaseStore(database: queue)
        let recording = try await store.recording(#require(RecordingID(string: id)))

        #expect(recording?.title == "Old meeting")
        #expect(recording?.duration == 120)
        #expect(recording?.folderID == nil)
        #expect(recording?.deletedAt == nil)
        #expect(recording?.attendees == [])
    }

    @Test func `library fields round-trip`() async throws {
        let store = try store()
        let folder = Folder(name: "Clients", createdAt: Date(timeIntervalSince1970: 1))
        try await store.insert(folder)
        let recording = Recording(
            title: "Sync",
            createdAt: Date(timeIntervalSince1970: 2),
            folderID: folder.id,
            deletedAt: Date(timeIntervalSince1970: 3),
            attendees: ["Ana", "Bruno"],
        )
        try await store.insert(recording)
        #expect(try await store.recording(recording.id) == recording)
        #expect(try await store.trashedRecordings().map(\.id) == [recording.id])
    }

    @Test func `deleting a folder keeps its recordings`() async throws {
        let store = try store()
        let folder = Folder(name: "Clients", createdAt: .now)
        try await store.insert(folder)
        let recording = Recording(title: "Sync", createdAt: .now, folderID: folder.id)
        try await store.insert(recording)
        try await store.delete(folder.id)
        #expect(try await store.recording(recording.id)?.folderID == nil)
    }

    @Test func `search finds titles and notes, in Japanese too, and skips the trash`() async throws {
        let store = try store()
        let meeting = Recording(title: "週次ミーティング", createdAt: .now)
        let trashed = Recording(title: "週次 old", createdAt: .now, deletedAt: .now)
        try await store.insert(meeting)
        try await store.insert(trashed)
        try await store.insert(Marker(recordingID: meeting.id, time: 42, kind: .note, text: "価格の決定"))

        #expect(try await store.search("週次").map(\.recording.id) == [meeting.id])
        let note = try #require(try await store.search("価格").first)
        #expect(note.time == 42)
        #expect(note.excerpt == "価格の決定")
    }

    @Test func `search treats wildcards as text`() async throws {
        let store = try store()
        try await store.insert(Recording(title: "Plain", createdAt: .now))
        try await store.insert(Recording(title: "100% done", createdAt: .now))
        #expect(try await store.search("%").map(\.recording.title) == ["100% done"])
        #expect(try await store.search("_").isEmpty)
    }

    @Test func `folder changes reach observers`() async throws {
        let store = try store()
        var iterator = store.observeFolders().makeAsyncIterator()
        #expect(await iterator.next()?.isEmpty == true)
        try await store.insert(Folder(name: "Clients", createdAt: .now))
        #expect(await iterator.next()?.map(\.name) == ["Clients"])
    }
}

struct TranscriptPersistenceTests {
    private func setUp() async throws -> (DatabaseStore, Recording) {
        let store = try DatabaseStore(database: DatabaseQueue())
        let recording = Recording(title: "Sync", createdAt: .now)
        try await store.insert(recording)
        return (store, recording)
    }

    private func segment(_ recording: Recording, _ start: Double, _ text: String) -> TranscriptSegment {
        TranscriptSegment(recordingID: recording.id, start: start, end: start + 1, text: text)
    }

    private func job(_ recording: Recording, checkpoint: Double) -> TranscriptionJob {
        TranscriptionJob(recordingID: recording.id, modelID: "m", language: "en", checkpoint: checkpoint)
    }

    @Test func `segments and the checkpoint save together`() async throws {
        let (store, recording) = try await setUp()
        try await store.append([segment(recording, 1, "Hello")], job: job(recording, checkpoint: 180))
        #expect(try await store.segments(for: recording.id).map(\.text) == ["Hello"])
        #expect(try await store.job(for: recording.id)?.checkpoint == 180)
    }

    @Test func `search finds transcripts, including Japanese, with the time`() async throws {
        let (store, recording) = try await setUp()
        try await store.append(
            [segment(recording, 75, "来週の価格改定について話しましょう"), segment(recording, 80, "Decide the launch date")],
            job: job(recording, checkpoint: 180),
        )
        #expect(try await store.search("launch").first?.time == 80)
        #expect(try await store.search("価格改定").first?.time == 75)
        #expect(try await store.search("価格").first?.time == 75, "Two characters fall back to LIKE")
    }

    @Test func `search reflects edits and deletions`() async throws {
        let (store, recording) = try await setUp()
        let original = segment(recording, 1, "Discuss pricing")
        try await store.append([original], job: job(recording, checkpoint: 10))

        var edited = original
        edited.text = "Discuss budget"
        try await store.update(edited)
        #expect(try await store.search("pricing").isEmpty)
        #expect(try await store.search("budget").count == 1)

        try await store.deleteTranscript(for: recording.id)
        #expect(try await store.search("budget").isEmpty)
    }

    @Test func `quotes in a search cannot break the query`() async throws {
        let (store, recording) = try await setUp()
        try await store.append([segment(recording, 1, "say \"hello\" now")], job: job(recording, checkpoint: 10))
        #expect(try await store.search("\"hello\"").count == 1)
    }

    @Test func `find and replace counts what changed`() async throws {
        let (store, recording) = try await setUp()
        try await store.append(
            [segment(recording, 1, "Hi Ana"), segment(recording, 2, "Bye"), segment(recording, 3, "Ana left")],
            job: job(recording, checkpoint: 10),
        )
        #expect(try await store.replaceAll(in: recording.id, of: "Ana", with: "Bruna") == 2)
        #expect(try await store.segments(for: recording.id).first?.text == "Hi Bruna")
    }

    @Test func `deleting a recording removes its transcript and search entries`() async throws {
        let (store, recording) = try await setUp()
        try await store.append([segment(recording, 1, "secret plan")], job: job(recording, checkpoint: 10))
        try await store.delete(recording.id)
        #expect(try await store.search("secret").isEmpty, "Deleted content must not stay searchable")
    }

    @Test func `selections default to automatic and can be pinned`() async throws {
        let (store, _) = try await setUp()
        #expect(try await store.selection(for: .transcription) == .automatic)
        try await store.setSelection(.pinned("whisper"), for: .transcription)
        #expect(try await store.selection(for: .transcription) == .pinned("whisper"))
        try await store.setSelection(.automatic, for: .transcription)
        #expect(try await store.selection(for: .transcription) == .automatic)
    }
}

struct SpeakerPersistenceTests {
    private func setUp() async throws -> (DatabaseStore, Recording) {
        let store = try DatabaseStore(database: DatabaseQueue())
        let recording = Recording(title: "Sync", createdAt: .now)
        try await store.insert(recording)
        return (store, recording)
    }

    private func phrase(_ store: DatabaseStore, _ recording: Recording) async throws -> TranscriptSegment {
        let segment = TranscriptSegment(recordingID: recording.id, start: 1, end: 2, text: "Hello Ana")
        let job = TranscriptionJob(recordingID: recording.id, modelID: "m", language: "en")
        try await store.append([segment], job: job)
        return segment
    }

    @Test func `speakers and assignments save together`() async throws {
        let (store, recording) = try await setUp()
        let segment = try await phrase(store, recording)
        let speaker = Speaker(recordingID: recording.id, number: 1, embedding: [0.5, -0.25], talkTime: 12)
        try await store.saveSpeakers([speaker], assignments: [segment.id: speaker.id], for: recording.id)

        #expect(try await store.speakers(for: recording.id) == [speaker], "The embedding must round-trip exactly")
        #expect(try await store.segments(for: recording.id).first?.speaker == speaker.id.uuidString)
    }

    @Test func `saving again replaces the speakers, so that a resumed job cannot duplicate them`() async throws {
        let (store, recording) = try await setUp()
        let first = Speaker(recordingID: recording.id, number: 1)
        try await store.saveSpeakers([first], assignments: [:], for: recording.id)
        let second = Speaker(recordingID: recording.id, number: 1)
        try await store.saveSpeakers([second], assignments: [:], for: recording.id)
        #expect(try await store.speakers(for: recording.id).map(\.id) == [second.id])
    }

    @Test func `merging moves the phrases and removes the speaker`() async throws {
        let (store, recording) = try await setUp()
        let segment = try await phrase(store, recording)
        let keep = Speaker(recordingID: recording.id, number: 1)
        let drop = Speaker(recordingID: recording.id, number: 2)
        try await store.saveSpeakers([keep, drop], assignments: [segment.id: drop.id], for: recording.id)
        try await store.merge(drop.id, into: keep.id)
        #expect(try await store.speakers(for: recording.id).map(\.id) == [keep.id])
        #expect(try await store.segments(for: recording.id).first?.speaker == keep.id.uuidString)
    }

    @Test func `renaming a person reaches their speakers`() async throws {
        let (store, recording) = try await setUp()
        var person = Person(name: "Ana", createdAt: .now)
        try await store.insert(person)
        let speaker = Speaker(recordingID: recording.id, number: 1, name: "Ana", personID: person.id)
        try await store.saveSpeakers([speaker], assignments: [:], for: recording.id)
        person.name = "Ana Lima"
        try await store.update(person)
        #expect(try await store.speakers(for: recording.id).first?.name == "Ana Lima")
    }

    @Test func `deleting a person erases the voice print and keeps the name in old transcripts`() async throws {
        let (store, recording) = try await setUp()
        let person = Person(name: "Ana", createdAt: .now)
        try await store.insert(person)
        try await store.save(VoicePrint(personID: person.id, modelID: "m", embedding: [1], talkTime: 20))
        let speaker = Speaker(recordingID: recording.id, number: 1, name: "Ana", personID: person.id)
        try await store.saveSpeakers([speaker], assignments: [:], for: recording.id)

        try await store.delete(person: person.id)

        #expect(try await store.voicePrints(modelID: "m").isEmpty, "Biometric data must really go away")
        let kept = try await store.speakers(for: recording.id).first
        #expect(kept?.name == "Ana")
        #expect(kept?.personID == nil)
    }

    @Test func `find and replace reaches speaker names`() async throws {
        let (store, recording) = try await setUp()
        _ = try await phrase(store, recording)
        let speaker = Speaker(recordingID: recording.id, number: 1, name: "Ana")
        try await store.saveSpeakers([speaker], assignments: [:], for: recording.id)
        #expect(try await store.replaceAll(in: recording.id, of: "Ana", with: "Bruna") == 2)
        #expect(try await store.speakers(for: recording.id).first?.name == "Bruna")
    }

    @Test func `voice prints stay apart per model`() async throws {
        let (store, _) = try await setUp()
        let person = Person(name: "Ana", createdAt: .now)
        try await store.insert(person)
        try await store.save(VoicePrint(personID: person.id, modelID: "a", embedding: [1], talkTime: 20))
        try await store.save(VoicePrint(personID: person.id, modelID: "b", embedding: [2], talkTime: 20))
        #expect(try await store.voicePrints(modelID: "a").first?.embedding == [1])
    }
}
