import Domain
import Foundation
import GRDB

/// SQLite storage. Every change to the schema is a new migration, and old migrations never change.
public final class DatabaseStore: RecordingStore, Sendable {
    let database: any DatabaseWriter

    /// Opens the database at a path, using WAL so that reads never block the recording.
    public convenience init(path: String) throws {
        try self.init(database: DatabasePool(path: path))
    }

    public init(database: any DatabaseWriter) throws {
        self.database = database
        try Self.migrator.migrate(database)
    }

    public func insert(_ recording: Recording) async throws {
        try await database.write { try RecordingRow(recording).insert($0) }
    }

    public func update(_ recording: Recording) async throws {
        try await database.write { try RecordingRow(recording).update($0) }
    }

    public func delete(_ id: RecordingID) async throws {
        try await database.write { db in
            // These answers quote the recording, and a deleted meeting must leave no words behind.
            try db.execute(
                sql: "DELETE FROM chatMessage WHERE role = 'assistant' AND citations LIKE ?",
                arguments: ["%\(id.rawValue.uuidString)%"],
            )
            _ = try RecordingRow.deleteOne(db, key: id.key)
        }
    }

    public func recording(_ id: RecordingID) async throws -> Recording? {
        try await database.read { try RecordingRow.fetchOne($0, key: id.key)?.model }
    }

    public func recordings(status: RecordingStatus) async throws -> [Recording] {
        try await database.read { db in
            try RecordingRow.filter(Column("status") == status.rawValue).fetchAll(db).compactMap(\.model)
        }
    }

    public func insert(_ marker: Marker) async throws {
        try await database.write { try MarkerRow(marker).insert($0) }
    }

    public func markers(for id: RecordingID) async throws -> [Marker] {
        try await database.read { db in
            try MarkerRow
                .filter(Column("recordingId") == id.key)
                .order(Column("time"))
                .fetchAll(db)
                .compactMap(\.model)
        }
    }

    public func insert(_ pause: PauseSpan) async throws {
        try await database.write { try PauseRow(pause).insert($0) }
    }

    public func pauses(for id: RecordingID) async throws -> [PauseSpan] {
        try await database.read { db in
            try PauseRow
                .filter(Column("recordingId") == id.key)
                .order(Column("position"))
                .fetchAll(db)
                .compactMap(\.model)
        }
    }

    public func trashedRecordings() async throws -> [Recording] {
        try await database.read { db in
            try RecordingRow
                .filter(Column("deletedAt") != nil)
                .order(Column("deletedAt").desc)
                .fetchAll(db)
                .compactMap(\.model)
        }
    }

    public func search(_ query: String) async throws -> [SearchHit] {
        let pattern = "%" + Self.escapeLike(query) + "%"
        return try await database.read { db in
            let titles = try RecordingRow.fetchAll(
                db,
                sql: """
                SELECT * FROM recording
                WHERE deletedAt IS NULL AND title LIKE ? ESCAPE '\\'
                ORDER BY createdAt DESC LIMIT 50
                """,
                arguments: [pattern],
            )
            .compactMap(\.model)
            .map { SearchHit(recording: $0) }

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT recording.*, marker.time AS hitTime, marker.text AS hitText
                FROM marker JOIN recording ON recording.id = marker.recordingId
                WHERE recording.deletedAt IS NULL AND marker.text LIKE ? ESCAPE '\\'
                ORDER BY recording.createdAt DESC, marker.time LIMIT 50
                """,
                arguments: [pattern],
            )
            let notes = try rows.compactMap { row -> SearchHit? in
                guard let recording = try RecordingRow(row: row).model else { return nil }
                return SearchHit(recording: recording, time: row["hitTime"], excerpt: row["hitText"])
            }
            return try titles + notes + Self.searchTranscripts(db, query: query, pattern: pattern)
        }
    }

    private static func searchTranscripts(_ db: Database, query: String, pattern: String) throws -> [SearchHit] {
        let columns = "recording.*, transcriptSegment.start AS hitTime, transcriptSegment.text AS hitText"
        let rows: [Row]
        if query.count >= 3 {
            let phrase = "\"" + query.replacing("\"", with: "\"\"") + "\""
            rows = try Row.fetchAll(
                db,
                sql: """
                SELECT \(columns) FROM transcriptSearch
                JOIN transcriptSegment ON transcriptSegment.rowid = transcriptSearch.rowid
                JOIN recording ON recording.id = transcriptSegment.recordingId
                WHERE transcriptSearch MATCH ? AND recording.deletedAt IS NULL
                ORDER BY recording.createdAt DESC, transcriptSegment.start LIMIT 50
                """,
                arguments: [phrase],
            )
        } else {
            rows = try Row.fetchAll(
                db,
                sql: """
                SELECT \(columns) FROM transcriptSegment
                JOIN recording ON recording.id = transcriptSegment.recordingId
                WHERE transcriptSegment.text LIKE ? ESCAPE '\\' AND recording.deletedAt IS NULL
                ORDER BY recording.createdAt DESC, transcriptSegment.start LIMIT 50
                """,
                arguments: [pattern],
            )
        }
        return try rows.compactMap { row in
            guard let recording = try RecordingRow(row: row).model else { return nil }
            return SearchHit(recording: recording, time: row["hitTime"], excerpt: row["hitText"])
        }
    }

    /// Search text comes from the user, and `%` or `_` must not act as wildcards.
    static func escapeLike(_ text: String) -> String {
        text.replacing("\\", with: "\\\\")
            .replacing("%", with: "\\%")
            .replacing("_", with: "\\_")
    }

    public func observeRecordings() -> AsyncStream<[Recording]> {
        observe { db in
            try RecordingRow.order(Column("createdAt").desc).fetchAll(db).compactMap(\.model)
        }
    }

    public func insert(_ folder: Folder) async throws {
        try await database.write { try FolderRow(folder).insert($0) }
    }

    public func update(_ folder: Folder) async throws {
        try await database.write { try FolderRow(folder).update($0) }
    }

    public func delete(_ folder: FolderID) async throws {
        _ = try await database.write { try FolderRow.deleteOne($0, key: folder.rawValue.uuidString) }
    }

    public func observeFolders() -> AsyncStream<[Folder]> {
        observe { db in
            try FolderRow.order(Column("createdAt")).fetchAll(db).compactMap(\.model)
        }
    }

    private func observe<Value: Sendable>(
        _ fetch: @escaping @Sendable (Database) throws -> Value,
    ) -> AsyncStream<Value> {
        let observation = ValueObservation.tracking(fetch)
        let database = database
        return AsyncStream { continuation in
            let task = Task {
                do {
                    for try await value in observation.values(in: database) {
                        continuation.yield(value)
                    }
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private extension RecordingID {
    var key: String {
        rawValue.uuidString
    }
}

private struct RecordingRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "recording"
    var id: String
    var title: String
    var createdAt: Date
    var duration: Double
    var status: String
    var wasRecovered: Bool
    var folderId: String?
    var deletedAt: Date?
    var attendees: [String]

    init(_ recording: Recording) {
        id = recording.id.key
        title = recording.title
        createdAt = recording.createdAt
        duration = recording.duration
        status = recording.status.rawValue
        wasRecovered = recording.wasRecovered
        folderId = recording.folderID?.rawValue.uuidString
        deletedAt = recording.deletedAt
        attendees = recording.attendees
    }

    var model: Recording? {
        guard let id = RecordingID(string: id), let status = RecordingStatus(rawValue: status) else { return nil }
        return Recording(
            id: id,
            title: title,
            createdAt: createdAt,
            duration: duration,
            status: status,
            wasRecovered: wasRecovered,
            folderID: folderId.flatMap(FolderID.init(string:)),
            deletedAt: deletedAt,
            attendees: attendees,
        )
    }
}

private struct FolderRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "folder"
    var id: String
    var name: String
    var createdAt: Date

    init(_ folder: Folder) {
        id = folder.id.rawValue.uuidString
        name = folder.name
        createdAt = folder.createdAt
    }

    var model: Folder? {
        FolderID(string: id).map { Folder(id: $0, name: name, createdAt: createdAt) }
    }
}

private struct MarkerRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "marker"
    var id: String
    var recordingId: String
    var time: Double
    var kind: String
    var text: String?
    var attachment: String?

    init(_ marker: Marker) {
        id = marker.id.uuidString
        recordingId = marker.recordingID.key
        time = marker.time
        kind = marker.kind.rawValue
        text = marker.text
        attachment = marker.attachment
    }

    var model: Marker? {
        guard
            let id = UUID(uuidString: id),
            let recordingID = RecordingID(string: recordingId),
            let kind = MarkerKind(rawValue: kind)
        else { return nil }
        return Marker(id: id, recordingID: recordingID, time: time, kind: kind, text: text, attachment: attachment)
    }
}

private struct PauseRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pauseSpan"
    var recordingId: String
    var position: Double
    var duration: Double
    var reason: String

    init(_ pause: PauseSpan) {
        recordingId = pause.recordingID.key
        position = pause.position
        duration = pause.duration
        reason = pause.reason.rawValue
    }

    var model: PauseSpan? {
        guard let id = RecordingID(string: recordingId), let reason = PauseReason(rawValue: reason) else { return nil }
        return PauseSpan(recordingID: id, position: position, duration: duration, reason: reason)
    }
}
