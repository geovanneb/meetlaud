import Accelerate
import Domain
import Foundation
import GRDB

extension DatabaseStore: ConversationStore {
    private static func conversation(_ row: Row) -> Conversation? {
        guard
            let id = UUID(uuidString: row["id"]),
            let scope = try? JSONDecoder().decode(AskScope.self, from: row["scope"] as Data)
        else { return nil }
        return Conversation(
            id: id, title: row["title"], scope: scope, createdAt: row["createdAt"], updatedAt: row["updatedAt"],
        )
    }

    private static func message(_ row: Row) -> ChatMessage? {
        guard
            let id = UUID(uuidString: row["id"]),
            let conversation = UUID(uuidString: row["conversationId"]),
            let role = ChatRole(rawValue: row["role"]),
            let state = AnswerState(rawValue: row["state"]),
            let citations = try? JSONDecoder().decode([Citation].self, from: row["citations"] as Data)
        else { return nil }
        return ChatMessage(
            id: id, conversationID: conversation, role: role, body: row["body"], citations: citations, state: state,
            createdAt: row["createdAt"],
        )
    }

    public func conversations() async throws -> [Conversation] {
        try await database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM conversation ORDER BY updatedAt DESC")
                .compactMap(Self.conversation)
        }
    }

    public func save(_ conversation: Conversation) async throws {
        try await database.write { db in
            // `OR REPLACE` deletes the row first, and the cascade would take every message with it.
            try db.execute(
                sql: """
                INSERT INTO conversation (id, title, scope, recordingId, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT (id) DO UPDATE SET
                    title = excluded.title, scope = excluded.scope, recordingId = excluded.recordingId,
                    updatedAt = excluded.updatedAt
                """,
                arguments: [
                    conversation.id.uuidString, conversation.title, JSONEncoder().encode(conversation.scope),
                    conversation.scope.recordingID?.rawValue.uuidString, conversation.createdAt,
                    conversation.updatedAt,
                ],
            )
        }
    }

    public func deleteConversation(_ id: UUID) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM conversation WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func messages(in conversation: UUID) async throws -> [ChatMessage] {
        try await database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM chatMessage WHERE conversationId = ? ORDER BY createdAt, role DESC",
                arguments: [conversation.uuidString],
            )
            .compactMap(Self.message)
        }
    }

    public func save(_ message: ChatMessage) async throws {
        try await database.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO chatMessage (id, conversationId, role, body, citations, state, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    message.id.uuidString, message.conversationID.uuidString, message.role.rawValue, message.body,
                    JSONEncoder().encode(message.citations), message.state.rawValue, message.createdAt,
                ],
            )
        }
    }

    public func memories() async throws -> [MemoryItem] {
        try await database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM memory ORDER BY createdAt").compactMap { row in
                UUID(uuidString: row["id"]).map { MemoryItem(id: $0, text: row["text"], createdAt: row["createdAt"]) }
            }
        }
    }

    public func save(_ memory: MemoryItem) async throws {
        try await database.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO memory (id, text, createdAt) VALUES (?, ?, ?)",
                arguments: [memory.id.uuidString, memory.text, memory.createdAt],
            )
        }
    }

    public func deleteMemory(_ id: UUID) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM memory WHERE id = ?", arguments: [id.uuidString])
        }
    }
}

extension DatabaseStore: KnowledgeStore {
    /// The part of a query that keeps it inside the scope and out of the trash.
    private static func filter(_ scope: AskScope) -> (sql: String, arguments: StatementArguments) {
        switch scope {
        case .library:
            ("recording.deletedAt IS NULL", [])
        case let .folder(id):
            ("recording.deletedAt IS NULL AND recording.folderId = ?", [id.rawValue.uuidString])
        case let .recording(id):
            ("recording.deletedAt IS NULL AND recording.id = ?", [id.rawValue.uuidString])
        }
    }

    private static func encode(_ vector: [Float]) -> Data {
        vector.withUnsafeBytes { Data($0) }
    }

    private static func decode(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private static func chunk(_ row: Row) -> KnowledgeChunk? {
        guard
            let id = UUID(uuidString: row["id"]),
            let recording = RecordingID(string: row["recordingId"])
        else { return nil }
        return KnowledgeChunk(
            id: id, recordingID: recording, start: row["start"], end: row["end"], text: row["text"],
            language: row["language"], modelID: row["modelId"],
            vector: (row["vector"] as Data?).map(decode),
        )
    }

    public func indexStates() async throws -> [RecordingID: KnowledgeIndexState] {
        try await database.read { db in
            var states: [RecordingID: KnowledgeIndexState] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT * FROM knowledgeIndex") {
                guard let id = RecordingID(string: row["recordingId"]) else { continue }
                states[id] = KnowledgeIndexState(sourceHash: row["sourceHash"], modelID: row["modelId"])
            }
            return states
        }
    }

    public func replaceChunks(
        _ chunks: [KnowledgeChunk],
        for id: RecordingID,
        state: KnowledgeIndexState,
    ) async throws {
        let key = id.rawValue.uuidString
        try await database.write { db in
            try db.execute(sql: "DELETE FROM knowledgeChunk WHERE recordingId = ?", arguments: [key])
            for chunk in chunks {
                try db.execute(
                    sql: """
                    INSERT INTO knowledgeChunk (id, recordingId, start, end, text, language, modelId, vector)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        chunk.id.uuidString, key, chunk.start, chunk.end, chunk.text, chunk.language, chunk.modelID,
                        chunk.vector.map(Self.encode),
                    ],
                )
            }
            try db.execute(
                sql: "INSERT OR REPLACE INTO knowledgeIndex (recordingId, sourceHash, modelId) VALUES (?, ?, ?)",
                arguments: [key, state.sourceHash, state.modelID],
            )
        }
    }

    public func removeChunks(for id: RecordingID) async throws {
        let key = id.rawValue.uuidString
        try await database.write { db in
            try db.execute(sql: "DELETE FROM knowledgeChunk WHERE recordingId = ?", arguments: [key])
            try db.execute(sql: "DELETE FROM knowledgeIndex WHERE recordingId = ?", arguments: [key])
        }
    }

    public func lexicalMatches(terms: [String], scope: AskScope, limit: Int) async throws -> [UUID] {
        let long = terms.filter { $0.count >= 3 }
        let short = terms.filter { $0.count < 3 }
        let filter = Self.filter(scope)
        return try await database.read { db in
            var found: [String] = []
            if !long.isEmpty {
                let query = long.map { "\"" + $0.replacing("\"", with: "\"\"") + "\"" }.joined(separator: " OR ")
                var arguments: StatementArguments = [query]
                arguments += filter.arguments
                arguments += [limit]
                found += try String.fetchAll(
                    db,
                    sql: """
                    SELECT knowledgeChunk.id FROM knowledgeSearch
                    JOIN knowledgeChunk ON knowledgeChunk.rowid = knowledgeSearch.rowid
                    JOIN recording ON recording.id = knowledgeChunk.recordingId
                    WHERE knowledgeSearch MATCH ? AND \(filter.sql)
                    ORDER BY bm25(knowledgeSearch) LIMIT ?
                    """,
                    arguments: arguments,
                )
            }
            // Trigrams cannot see two characters, and two Japanese characters are often the word that matters.
            for term in short {
                var arguments: StatementArguments = ["%" + Self.escapeLike(term) + "%"]
                arguments += filter.arguments
                arguments += [limit]
                found += try String.fetchAll(
                    db,
                    sql: """
                    SELECT knowledgeChunk.id FROM knowledgeChunk
                    JOIN recording ON recording.id = knowledgeChunk.recordingId
                    WHERE knowledgeChunk.text LIKE ? ESCAPE '\\' AND \(filter.sql)
                    LIMIT ?
                    """,
                    arguments: arguments,
                )
            }
            return found.compactMap(UUID.init(uuidString:))
        }
    }

    public func nearest(to vector: [Float], modelID: String, scope: AskScope, limit: Int) async throws -> [UUID] {
        let filter = Self.filter(scope)
        let expected = vector.count * MemoryLayout<Float>.size
        return try await database.read { db in
            var arguments: StatementArguments = [modelID]
            arguments += filter.arguments
            // One row at a time. Holding every vector of a large library at once is how an app gets killed.
            let cursor = try Row.fetchCursor(
                db,
                sql: """
                SELECT knowledgeChunk.id AS id, knowledgeChunk.vector AS vector FROM knowledgeChunk
                JOIN recording ON recording.id = knowledgeChunk.recordingId
                WHERE knowledgeChunk.modelId = ? AND knowledgeChunk.vector IS NOT NULL AND \(filter.sql)
                """,
                arguments: arguments,
            )
            var best: [(id: String, score: Float)] = []
            while let row = try cursor.next() {
                guard let data = row["vector"] as Data?, data.count == expected else { continue }
                let score = data.withUnsafeBytes { bytes -> Float in
                    guard let pointer = bytes.bindMemory(to: Float.self).baseAddress else { return -1 }
                    var result: Float = 0
                    vDSP_dotpr(vector, 1, pointer, 1, &result, vDSP_Length(vector.count))
                    return result
                }
                if best.count < limit || score > (best.last?.score ?? -1) {
                    let position = best.firstIndex { $0.score < score } ?? best.count
                    best.insert((row["id"], score), at: position)
                    if best.count > limit {
                        best.removeLast()
                    }
                }
            }
            return best.compactMap { UUID(uuidString: $0.id) }
        }
    }

    public func chunks(_ ids: [UUID]) async throws -> [KnowledgeChunk] {
        guard !ids.isEmpty else { return [] }
        return try await database.read { db in
            let marks = databaseQuestionMarks(count: ids.count)
            return try Row.fetchAll(
                db,
                sql: "SELECT * FROM knowledgeChunk WHERE id IN (\(marks))",
                arguments: StatementArguments(ids.map(\.uuidString)),
            )
            .compactMap(Self.chunk)
        }
    }
}
