import Domain
import Foundation
import GRDB

extension DatabaseStore: SpeakerStore {
    private static func encode(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func decode(_ data: Data?) -> [Float] {
        guard let data else { return [] }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private static func speaker(_ row: Row, id: RecordingID) -> Speaker? {
        guard let uuid = UUID(uuidString: row["id"]) else { return nil }
        let person: String? = row["personId"]
        return Speaker(
            id: uuid,
            recordingID: id,
            number: row["number"],
            name: row["name"],
            personID: person.flatMap(UUID.init(uuidString:)),
            isSuggested: row["isSuggested"],
            embedding: decode(row["embedding"]),
            talkTime: row["talkTime"],
        )
    }

    public func speakers(for id: RecordingID) async throws -> [Speaker] {
        try await database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM speaker WHERE recordingId = ? ORDER BY number",
                arguments: [id.rawValue.uuidString],
            )
            .compactMap { Self.speaker($0, id: id) }
        }
    }

    public func saveSpeakers(_ speakers: [Speaker], assignments: [UUID: UUID], for id: RecordingID) async throws {
        try await database.write { db in
            let key = id.rawValue.uuidString
            try db.execute(sql: "UPDATE transcriptSegment SET speaker = NULL WHERE recordingId = ?", arguments: [key])
            try db.execute(sql: "DELETE FROM speaker WHERE recordingId = ?", arguments: [key])
            for speaker in speakers {
                try Self.insert(speaker, db: db)
            }
            for (segment, speaker) in assignments {
                try db.execute(
                    sql: "UPDATE transcriptSegment SET speaker = ? WHERE id = ?",
                    arguments: [speaker.uuidString, segment.uuidString],
                )
            }
        }
    }

    private static func insert(_ speaker: Speaker, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO speaker (id, recordingId, number, name, personId, isSuggested, embedding, talkTime)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                speaker.id.uuidString, speaker.recordingID.rawValue.uuidString, speaker.number, speaker.name,
                speaker.personID?.uuidString, speaker.isSuggested, encode(speaker.embedding), speaker.talkTime,
            ],
        )
    }

    public func update(_ speaker: Speaker) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE speaker SET name = ?, personId = ?, isSuggested = ? WHERE id = ?",
                arguments: [speaker.name, speaker.personID?.uuidString, speaker.isSuggested, speaker.id.uuidString],
            )
        }
    }

    public func setSpeaker(_ speakerID: UUID, forSegment segmentID: UUID) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE transcriptSegment SET speaker = ? WHERE id = ?",
                arguments: [speakerID.uuidString, segmentID.uuidString],
            )
        }
    }

    public func merge(_ source: UUID, into target: UUID) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE transcriptSegment SET speaker = ? WHERE speaker = ?",
                arguments: [target.uuidString, source.uuidString],
            )
            try db.execute(sql: "DELETE FROM speaker WHERE id = ?", arguments: [source.uuidString])
        }
    }

    public func people() async throws -> [Person] {
        try await database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM person ORDER BY name COLLATE NOCASE").compactMap { row in
                UUID(uuidString: row["id"]).map { Person(id: $0, name: row["name"], createdAt: row["createdAt"]) }
            }
        }
    }

    public func insert(_ person: Person) async throws {
        try await database.write { db in
            try db.execute(
                sql: "INSERT INTO person (id, name, createdAt) VALUES (?, ?, ?)",
                arguments: [person.id.uuidString, person.name, person.createdAt],
            )
        }
    }

    public func update(_ person: Person) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE person SET name = ? WHERE id = ?",
                arguments: [person.name, person.id.uuidString],
            )
            try db.execute(
                sql: "UPDATE speaker SET name = ? WHERE personId = ?",
                arguments: [person.name, person.id.uuidString],
            )
        }
    }

    public func delete(person id: UUID) async throws {
        try await database.write { db in
            // Voice prints go through the foreign key. Names in old transcripts stay, and stop being linked.
            try db.execute(sql: "UPDATE speaker SET personId = NULL WHERE personId = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM person WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func merge(person source: UUID, into target: Person) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE speaker SET personId = ?, name = ? WHERE personId = ?",
                arguments: [target.id.uuidString, target.name, source.uuidString],
            )
            try db.execute(
                sql: "UPDATE OR IGNORE voicePrint SET personId = ? WHERE personId = ?",
                arguments: [target.id.uuidString, source.uuidString],
            )
            // Any voice print left here lost to the target's, and goes with the person through the foreign key.
            try db.execute(sql: "DELETE FROM person WHERE id = ?", arguments: [source.uuidString])
        }
    }

    public func voicePrints(modelID: String) async throws -> [VoicePrint] {
        try await database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM voicePrint WHERE modelId = ?", arguments: [modelID])
                .compactMap { row in
                    UUID(uuidString: row["personId"]).map {
                        VoicePrint(
                            personID: $0, modelID: modelID,
                            embedding: Self.decode(row["embedding"]), talkTime: row["talkTime"],
                        )
                    }
                }
        }
    }

    public func save(_ print: VoicePrint) async throws {
        try await database.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO voicePrint (personId, modelId, embedding, talkTime) VALUES (?, ?, ?, ?)",
                arguments: [print.personID.uuidString, print.modelID, Self.encode(print.embedding), print.talkTime],
            )
        }
    }

    public func recordings(with person: UUID) async throws -> [RecordingID] {
        try await database.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT DISTINCT recordingId FROM speaker WHERE personId = ?",
                arguments: [person.uuidString],
            )
            .compactMap(RecordingID.init(string:))
        }
    }
}
