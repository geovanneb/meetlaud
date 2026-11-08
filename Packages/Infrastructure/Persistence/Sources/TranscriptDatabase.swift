import Domain
import Foundation
import GRDB

extension DatabaseStore: TranscriptStore, ModelUsageStore {
    // MARK: - Transcript

    public func transcript(for id: RecordingID) async throws -> Transcript? {
        try await database.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM transcript WHERE recordingId = ?",
                arguments: [id.rawValue.uuidString],
            )
            .map {
                Transcript(
                    recordingID: id, modelID: $0["modelId"], language: $0["language"], isComplete: $0["isComplete"],
                )
            }
        }
    }

    public func save(_ transcript: Transcript) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO transcript (recordingId, modelId, language, isComplete) VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    transcript.recordingID.rawValue.uuidString, transcript.modelID,
                    transcript.language, transcript.isComplete,
                ],
            )
        }
    }

    public func segments(for id: RecordingID) async throws -> [TranscriptSegment] {
        try await database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM transcriptSegment WHERE recordingId = ? ORDER BY start",
                arguments: [id.rawValue.uuidString],
            )
            .compactMap { Self.segment($0, id: id) }
        }
    }

    private static func segment(_ row: Row, id: RecordingID) -> TranscriptSegment? {
        guard let uuid = UUID(uuidString: row["id"]) else { return nil }
        return TranscriptSegment(
            id: uuid, recordingID: id, start: row["start"], end: row["end"], text: row["text"], speaker: row["speaker"],
        )
    }

    public func append(_ segments: [TranscriptSegment], job: TranscriptionJob) async throws {
        try await database.write { db in
            for segment in segments {
                try db.execute(
                    sql: """
                    INSERT INTO transcriptSegment (id, recordingId, start, end, text, speaker)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        segment.id.uuidString, segment.recordingID.rawValue.uuidString, segment.start,
                        segment.end, segment.text, segment.speaker,
                    ],
                )
            }
            try Self.write(job, db: db)
        }
    }

    public func update(_ segment: TranscriptSegment) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE transcriptSegment SET text = ?, speaker = ? WHERE id = ?",
                arguments: [segment.text, segment.speaker, segment.id.uuidString],
            )
        }
    }

    public func replaceAll(in id: RecordingID, of text: String, with replacement: String) async throws -> Int {
        guard !text.isEmpty else { return 0 }
        return try await database.write { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, text FROM transcriptSegment WHERE recordingId = ?",
                arguments: [id.rawValue.uuidString],
            )
            var count = 0
            for row in rows {
                let original: String = row["text"]
                let updated = original.replacing(text, with: replacement)
                if updated != original {
                    let rowID: String = row["id"]
                    try db.execute(
                        sql: "UPDATE transcriptSegment SET text = ? WHERE id = ?",
                        arguments: [updated, rowID],
                    )
                    count += 1
                }
            }
            let names = try Row.fetchAll(
                db,
                sql: "SELECT id, name FROM speaker WHERE recordingId = ? AND name IS NOT NULL",
                arguments: [id.rawValue.uuidString],
            )
            for row in names {
                let original: String = row["name"]
                let updated = original.replacing(text, with: replacement)
                if updated != original {
                    let rowID: String = row["id"]
                    try db.execute(sql: "UPDATE speaker SET name = ? WHERE id = ?", arguments: [updated, rowID])
                    count += 1
                }
            }
            return count
        }
    }

    public func deleteTranscript(for id: RecordingID) async throws {
        try await database.write { db in
            let key = id.rawValue.uuidString
            try db.execute(sql: "DELETE FROM transcriptSegment WHERE recordingId = ?", arguments: [key])
            try db.execute(sql: "DELETE FROM transcript WHERE recordingId = ?", arguments: [key])
        }
    }

    // MARK: - Versions

    private struct StoredSegment: Codable {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    public func versions(for id: RecordingID) async throws -> [TranscriptVersion] {
        try await database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM transcriptVersion WHERE recordingId = ? ORDER BY savedAt DESC",
                arguments: [id.rawValue.uuidString],
            )
            .compactMap { row in
                guard let versionID = UUID(uuidString: row["id"]),
                      let data = row["segments"] as Data?,
                      let stored = try? JSONDecoder().decode([StoredSegment].self, from: data)
                else { return nil }
                return TranscriptVersion(
                    id: versionID,
                    recordingID: id,
                    modelID: row["modelId"],
                    language: row["language"],
                    savedAt: Date(timeIntervalSince1970: row["savedAt"]),
                    segments: stored.map {
                        TranscriptSegment(recordingID: id, start: $0.start, end: $0.end, text: $0.text)
                    },
                )
            }
        }
    }

    public func save(_ version: TranscriptVersion) async throws {
        let stored = version.segments.map { StoredSegment(start: $0.start, end: $0.end, text: $0.text) }
        let data = try JSONEncoder().encode(stored)
        try await database.write { db in
            let key = version.recordingID.rawValue.uuidString
            try db.execute(
                sql: """
                INSERT INTO transcriptVersion (id, recordingId, modelId, language, savedAt, segments)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    version.id.uuidString, key, version.modelID, version.language,
                    version.savedAt.timeIntervalSince1970, data,
                ],
            )
            try db.execute(
                sql: """
                DELETE FROM transcriptVersion WHERE recordingId = ? AND id NOT IN (
                    SELECT id FROM transcriptVersion WHERE recordingId = ? ORDER BY savedAt DESC LIMIT ?
                )
                """,
                arguments: [key, key, TranscriptVersion.limit],
            )
        }
    }

    public func deleteVersion(_ id: UUID) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM transcriptVersion WHERE id = ?", arguments: [id.uuidString])
        }
    }

    // MARK: - Jobs

    private static func write(_ job: TranscriptionJob, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO transcriptionJob (recordingId, modelId, language, checkpoint, state, createdAt)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(recordingId) DO UPDATE SET
                language = excluded.language, checkpoint = excluded.checkpoint, state = excluded.state
            """,
            arguments: [
                job.recordingID.rawValue.uuidString, job.modelID, job.language,
                job.checkpoint, job.state.rawValue, Date(),
            ],
        )
    }

    private static func job(_ row: Row) -> TranscriptionJob? {
        guard let id = RecordingID(string: row["recordingId"]), let state = JobState(rawValue: row["state"]) else {
            return nil
        }
        return TranscriptionJob(
            recordingID: id, modelID: row["modelId"], language: row["language"],
            checkpoint: row["checkpoint"], state: state,
        )
    }

    public func job(for id: RecordingID) async throws -> TranscriptionJob? {
        try await database.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM transcriptionJob WHERE recordingId = ?",
                arguments: [id.rawValue.uuidString],
            )
            .flatMap(Self.job)
        }
    }

    public func jobs() async throws -> [TranscriptionJob] {
        try await database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM transcriptionJob ORDER BY createdAt").compactMap(Self.job)
        }
    }

    public func save(_ job: TranscriptionJob) async throws {
        try await database.write { try Self.write(job, db: $0) }
    }

    public func deleteJob(for id: RecordingID) async throws {
        try await database.write { db in
            try db.execute(
                sql: "DELETE FROM transcriptionJob WHERE recordingId = ?",
                arguments: [id.rawValue.uuidString],
            )
        }
    }

    // MARK: - Models

    public func selection(for role: ModelRole) async throws -> SelectionMode {
        try await database.read { db in
            let model = try String.fetchOne(
                db,
                sql: "SELECT modelId FROM roleSelection WHERE role = ?",
                arguments: [role.rawValue],
            )
            return model.map(SelectionMode.pinned) ?? .automatic
        }
    }

    public func setSelection(_ mode: SelectionMode, for role: ModelRole) async throws {
        try await database.write { db in
            switch mode {
            case .automatic:
                try db.execute(sql: "DELETE FROM roleSelection WHERE role = ?", arguments: [role.rawValue])
            case let .pinned(id):
                try db.execute(
                    sql: "INSERT OR REPLACE INTO roleSelection (role, modelId) VALUES (?, ?)",
                    arguments: [role.rawValue, id],
                )
            }
        }
    }

    public func insert(_ stat: ModelRunStat) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO modelRunStat (modelId, audioDuration, wallTime, outcome, date) VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [stat.modelID, stat.audioDuration, stat.wallTime, stat.outcome.rawValue, stat.date],
            )
        }
    }

    public func stats() async throws -> [ModelRunStat] {
        try await database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM modelRunStat ORDER BY date DESC LIMIT 500").compactMap { row in
                guard let outcome = ModelRunStat.Outcome(rawValue: row["outcome"]) else { return nil }
                return ModelRunStat(
                    modelID: row["modelId"], audioDuration: row["audioDuration"],
                    wallTime: row["wallTime"], outcome: outcome, date: row["date"],
                )
            }
        }
    }

    public func logNetwork(_ entry: NetworkLogEntry) async throws {
        try await database.write { db in
            try db.execute(
                sql: "INSERT INTO networkLog (id, host, modelId, bytes, date) VALUES (?, ?, ?, ?, ?)",
                arguments: [entry.id.uuidString, entry.host, entry.modelID, entry.bytes, entry.date],
            )
        }
    }

    public func clearNetworkLog() async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM networkLog")
        }
    }

    public func networkLog() async throws -> [NetworkLogEntry] {
        try await database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM networkLog ORDER BY date DESC").compactMap { row in
                guard let id = UUID(uuidString: row["id"]) else { return nil }
                return NetworkLogEntry(
                    id: id, host: row["host"], modelID: row["modelId"], bytes: row["bytes"], date: row["date"],
                )
            }
        }
    }
}
