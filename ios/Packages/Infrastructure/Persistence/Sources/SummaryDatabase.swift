import Domain
import Foundation
import GRDB

extension DatabaseStore: SummaryStore {
    private static func summary(_ row: Row, id: RecordingID) -> Summary? {
        guard
            let uuid = UUID(uuidString: row["id"]),
            let sections = try? JSONDecoder().decode([SummarySection].self, from: row["sections"] as Data)
        else { return nil }
        return Summary(
            id: uuid,
            recordingID: id,
            templateName: row["templateName"],
            modelID: row["modelId"],
            language: row["language"],
            sections: sections,
            isComplete: row["isComplete"],
            createdAt: row["createdAt"],
        )
    }

    private static func write(_ summary: Summary, db: Database) throws {
        // `OR REPLACE` deletes the row first, and the cascade would take the job with it.
        try db.execute(
            sql: """
            INSERT INTO summary
            (id, recordingId, templateName, modelId, language, sections, isComplete, createdAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET sections = excluded.sections, isComplete = excluded.isComplete
            """,
            arguments: [
                summary.id.uuidString, summary.recordingID.rawValue.uuidString, summary.templateName, summary.modelID,
                summary.language, JSONEncoder().encode(summary.sections), summary.isComplete, summary.createdAt,
            ],
        )
    }

    private static func write(_ job: SummaryJob, db: Database) throws {
        // Updates in place: `OR REPLACE` would move the job to the back of the queue.
        try db.execute(
            sql: """
            INSERT INTO summaryJob (summaryId, payload, createdAt) VALUES (?, ?, ?)
            ON CONFLICT (summaryId) DO UPDATE SET payload = excluded.payload
            """,
            arguments: [job.summaryID.uuidString, JSONEncoder().encode(job), Date()],
        )
    }

    public func summaries(for id: RecordingID) async throws -> [Summary] {
        try await database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM summary WHERE recordingId = ? ORDER BY createdAt",
                arguments: [id.rawValue.uuidString],
            )
            .compactMap { Self.summary($0, id: id) }
        }
    }

    public func save(_ summary: Summary) async throws {
        try await database.write { try Self.write(summary, db: $0) }
    }

    public func save(_ summary: Summary, job: SummaryJob) async throws {
        try await database.write { db in
            try Self.write(summary, db: db)
            try Self.write(job, db: db)
        }
    }

    public func complete(_ summary: Summary) async throws {
        try await database.write { db in
            var finished = summary
            finished.isComplete = true
            try Self.write(finished, db: db)
            try db.execute(sql: "DELETE FROM summaryJob WHERE summaryId = ?", arguments: [summary.id.uuidString])
        }
    }

    public func deleteSummary(_ id: UUID) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM summary WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func summaryJobs() async throws -> [SummaryJob] {
        try await database.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM summaryJob ORDER BY createdAt, summaryId")
                .compactMap { try? JSONDecoder().decode(SummaryJob.self, from: $0) }
        }
    }

    public func save(_ job: SummaryJob) async throws {
        try await database.write { try Self.write(job, db: $0) }
    }

    public func deleteSummaryJob(_ summaryID: UUID) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM summaryJob WHERE summaryId = ?", arguments: [summaryID.uuidString])
        }
    }

    public func userTemplates() async throws -> [SummaryTemplate] {
        try await database.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM summaryTemplate")
                .compactMap { try? JSONDecoder().decode(SummaryTemplate.self, from: $0) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    public func save(_ template: SummaryTemplate) async throws {
        try await database.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO summaryTemplate (id, payload) VALUES (?, ?)",
                arguments: [template.id, JSONEncoder().encode(template)],
            )
        }
    }

    public func deleteTemplate(_ id: String) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM summaryTemplate WHERE id = ?", arguments: [id])
        }
    }
}
