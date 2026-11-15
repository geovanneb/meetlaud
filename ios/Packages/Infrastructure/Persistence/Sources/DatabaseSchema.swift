import Foundation
import GRDB

/// Every change to the schema is a new migration. Old migrations never change, since phones already ran them.
extension DatabaseStore {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "recording") { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("createdAt", .datetime).notNull().indexed()
                table.column("duration", .double).notNull()
                table.column("status", .text).notNull().indexed()
                table.column("wasRecovered", .boolean).notNull()
            }
            try db.create(table: "marker") { table in
                table.column("id", .text).primaryKey()
                table.belongsTo("recording", onDelete: .cascade).notNull()
                table.column("time", .double).notNull()
                table.column("kind", .text).notNull()
                table.column("text", .text)
                table.column("attachment", .text)
            }
            try db.create(table: "pauseSpan") { table in
                table.autoIncrementedPrimaryKey("id")
                table.belongsTo("recording", onDelete: .cascade).notNull()
                table.column("position", .double).notNull()
                table.column("duration", .double).notNull()
                table.column("reason", .text).notNull()
            }
        }
        migrator.registerMigration("v2-library") { db in
            try db.create(table: "folder") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("createdAt", .datetime).notNull()
            }
            try db.alter(table: "recording") { table in
                table.add(column: "folderId", .text).references("folder", onDelete: .setNull)
                table.add(column: "deletedAt", .datetime)
                table.add(column: "attendees", .text).notNull().defaults(to: "[]")
            }
        }
        migrator.registerMigration("v3-models") { db in
            try db.create(table: "transcript") { table in
                table.column("recordingId", .text).primaryKey()
                    .references("recording", onDelete: .cascade)
                table.column("modelId", .text).notNull()
                table.column("language", .text)
                table.column("isComplete", .boolean).notNull()
            }
            try db.create(table: "transcriptSegment") { table in
                table.column("id", .text).primaryKey()
                table.column("recordingId", .text).notNull().indexed()
                    .references("recording", onDelete: .cascade)
                table.column("start", .double).notNull()
                table.column("end", .double).notNull()
                table.column("text", .text).notNull()
                table.column("speaker", .text)
            }
            // Trigram finds Japanese with no word segmentation. Queries under 3 characters fall back to LIKE.
            try db.execute(sql: """
            CREATE VIRTUAL TABLE transcriptSearch USING fts5(
                text, content='transcriptSegment', content_rowid='rowid', tokenize='trigram'
            );
            CREATE TRIGGER transcriptSearchInsert AFTER INSERT ON transcriptSegment BEGIN
                INSERT INTO transcriptSearch(rowid, text) VALUES (new.rowid, new.text);
            END;
            CREATE TRIGGER transcriptSearchDelete AFTER DELETE ON transcriptSegment BEGIN
                INSERT INTO transcriptSearch(transcriptSearch, rowid, text) VALUES ('delete', old.rowid, old.text);
            END;
            CREATE TRIGGER transcriptSearchUpdate AFTER UPDATE OF text ON transcriptSegment BEGIN
                INSERT INTO transcriptSearch(transcriptSearch, rowid, text) VALUES ('delete', old.rowid, old.text);
                INSERT INTO transcriptSearch(rowid, text) VALUES (new.rowid, new.text);
            END;
            """)
            try db.create(table: "transcriptionJob") { table in
                table.column("recordingId", .text).primaryKey()
                    .references("recording", onDelete: .cascade)
                table.column("modelId", .text).notNull()
                table.column("language", .text)
                table.column("checkpoint", .double).notNull()
                table.column("state", .text).notNull()
                table.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "roleSelection") { table in
                table.column("role", .text).primaryKey()
                table.column("modelId", .text)
            }
            try db.create(table: "modelRunStat") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("modelId", .text).notNull().indexed()
                table.column("audioDuration", .double).notNull()
                table.column("wallTime", .double).notNull()
                table.column("outcome", .text).notNull()
                table.column("date", .datetime).notNull()
            }
            try db.create(table: "networkLog") { table in
                table.column("id", .text).primaryKey()
                table.column("host", .text).notNull()
                table.column("modelId", .text).notNull()
                table.column("bytes", .integer).notNull()
                table.column("date", .datetime).notNull()
            }
        }
        migrator.registerMigration("v4-speakers") { db in
            try db.create(table: "person") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "speaker") { table in
                table.column("id", .text).primaryKey()
                table.column("recordingId", .text).notNull().indexed()
                    .references("recording", onDelete: .cascade)
                table.column("number", .integer).notNull()
                table.column("name", .text)
                table.column("personId", .text).indexed()
                table.column("isSuggested", .boolean).notNull()
                table.column("embedding", .blob)
                table.column("talkTime", .double).notNull()
            }
            try db.create(table: "voicePrint") { table in
                table.column("personId", .text).notNull()
                    .references("person", onDelete: .cascade)
                table.column("modelId", .text).notNull()
                table.column("embedding", .blob).notNull()
                table.column("talkTime", .double).notNull()
                table.primaryKey(["personId", "modelId"])
            }
        }
        migrator.registerMigration("v5-summaries") { db in
            try db.create(table: "summary") { table in
                table.column("id", .text).primaryKey()
                table.column("recordingId", .text).notNull().indexed()
                    .references("recording", onDelete: .cascade)
                table.column("templateName", .text).notNull()
                table.column("modelId", .text).notNull()
                table.column("language", .text)
                table.column("sections", .blob).notNull()
                table.column("isComplete", .boolean).notNull()
                table.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "summaryJob") { table in
                table.column("summaryId", .text).primaryKey()
                    .references("summary", onDelete: .cascade)
                table.column("payload", .blob).notNull()
                table.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "summaryTemplate") { table in
                table.column("id", .text).primaryKey()
                table.column("payload", .blob).notNull()
            }
        }
        migrator.registerMigration("v6-ask") { db in
            try db.create(table: "conversation") { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("scope", .blob).notNull()
                // A chat about one meeting has no reason to outlive it.
                table.column("recordingId", .text).indexed().references("recording", onDelete: .cascade)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull().indexed()
            }
            try db.create(table: "chatMessage") { table in
                table.column("id", .text).primaryKey()
                table.column("conversationId", .text).notNull().indexed()
                    .references("conversation", onDelete: .cascade)
                table.column("role", .text).notNull()
                table.column("body", .text).notNull()
                table.column("citations", .blob).notNull()
                table.column("state", .text).notNull()
                table.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "memory") { table in
                table.column("id", .text).primaryKey()
                table.column("text", .text).notNull()
                table.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "knowledgeChunk") { table in
                table.column("id", .text).primaryKey()
                table.column("recordingId", .text).notNull().indexed()
                    .references("recording", onDelete: .cascade)
                table.column("start", .double).notNull()
                table.column("end", .double).notNull()
                table.column("text", .text).notNull()
                table.column("language", .text)
                table.column("modelId", .text).indexed()
                table.column("vector", .blob)
            }
            try db.create(table: "knowledgeIndex") { table in
                table.column("recordingId", .text).primaryKey()
                    .references("recording", onDelete: .cascade)
                table.column("sourceHash", .text).notNull()
                table.column("modelId", .text)
            }
            try db.execute(sql: """
            CREATE VIRTUAL TABLE knowledgeSearch USING fts5(
                text, content='knowledgeChunk', content_rowid='rowid', tokenize='trigram'
            );
            CREATE TRIGGER knowledgeSearchInsert AFTER INSERT ON knowledgeChunk BEGIN
                INSERT INTO knowledgeSearch(rowid, text) VALUES (new.rowid, new.text);
            END;
            CREATE TRIGGER knowledgeSearchDelete AFTER DELETE ON knowledgeChunk BEGIN
                INSERT INTO knowledgeSearch(knowledgeSearch, rowid, text) VALUES ('delete', old.rowid, old.text);
            END;
            """)
        }
        migrator.registerMigration("v7-transcript-versions") { db in
            try db.create(table: "transcriptVersion") { table in
                table.column("id", .text).primaryKey()
                table.column("recordingId", .text).notNull().indexed()
                    .references("recording", onDelete: .cascade)
                table.column("modelId", .text).notNull()
                table.column("language", .text)
                table.column("savedAt", .double).notNull()
                table.column("segments", .blob).notNull()
            }
        }
        return migrator
    }
}
