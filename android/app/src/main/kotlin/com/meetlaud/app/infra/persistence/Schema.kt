package com.meetlaud.app.infra.persistence

/**
 * The same tables as ios/Packages/Infrastructure/Persistence/Sources/DatabaseSchema.swift, migration for migration.
 * The names go in GRDB's own `grdb_migrations` table, so a file made here opens on iOS and the other way round.
 * Old migrations never change, since phones already ran them.
 */
internal object Schema {
    val migrations: List<Pair<String, List<String>>> = listOf(
        "v1" to listOf(
            """CREATE TABLE "recording" ("id" TEXT PRIMARY KEY, "title" TEXT NOT NULL, "createdAt" DATETIME NOT NULL, "duration" DOUBLE NOT NULL, "status" TEXT NOT NULL, "wasRecovered" BOOLEAN NOT NULL)""",
            """CREATE INDEX "recording_on_createdAt" ON "recording"("createdAt")""",
            """CREATE INDEX "recording_on_status" ON "recording"("status")""",
            """CREATE TABLE "marker" ("id" TEXT PRIMARY KEY, "recordingId" TEXT NOT NULL REFERENCES "recording"("id") ON DELETE CASCADE, "time" DOUBLE NOT NULL, "kind" TEXT NOT NULL, "text" TEXT, "attachment" TEXT)""",
            """CREATE INDEX "index_marker_on_recordingId" ON "marker"("recordingId")""",
            """CREATE TABLE "pauseSpan" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "recordingId" TEXT NOT NULL REFERENCES "recording"("id") ON DELETE CASCADE, "position" DOUBLE NOT NULL, "duration" DOUBLE NOT NULL, "reason" TEXT NOT NULL)""",
            """CREATE INDEX "index_pauseSpan_on_recordingId" ON "pauseSpan"("recordingId")""",
        ),
        "v2-library" to listOf(
            """CREATE TABLE "folder" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "createdAt" DATETIME NOT NULL)""",
            """ALTER TABLE "recording" ADD COLUMN "folderId" TEXT REFERENCES "folder"("id") ON DELETE SET NULL""",
            """ALTER TABLE "recording" ADD COLUMN "deletedAt" DATETIME""",
            """ALTER TABLE "recording" ADD COLUMN "attendees" TEXT NOT NULL DEFAULT '[]'""",
        ),
        "v3-models" to listOf(
            """CREATE TABLE "transcript" ("recordingId" TEXT PRIMARY KEY REFERENCES "recording"("id") ON DELETE CASCADE, "modelId" TEXT NOT NULL, "language" TEXT, "isComplete" BOOLEAN NOT NULL)""",
            """CREATE TABLE "transcriptSegment" ("id" TEXT PRIMARY KEY, "recordingId" TEXT NOT NULL REFERENCES "recording"("id") ON DELETE CASCADE, "start" DOUBLE NOT NULL, "end" DOUBLE NOT NULL, "text" TEXT NOT NULL, "speaker" TEXT)""",
            """CREATE INDEX "transcriptSegment_on_recordingId" ON "transcriptSegment"("recordingId")""",
            // Trigram finds Japanese with no word segmentation. Queries under 3 characters fall back to LIKE (D-037).
            """CREATE VIRTUAL TABLE transcriptSearch USING fts5(text, content='transcriptSegment', content_rowid='rowid', tokenize='trigram')""",
            """CREATE TRIGGER transcriptSearchInsert AFTER INSERT ON transcriptSegment BEGIN INSERT INTO transcriptSearch(rowid, text) VALUES (new.rowid, new.text); END""",
            """CREATE TRIGGER transcriptSearchDelete AFTER DELETE ON transcriptSegment BEGIN INSERT INTO transcriptSearch(transcriptSearch, rowid, text) VALUES ('delete', old.rowid, old.text); END""",
            """CREATE TRIGGER transcriptSearchUpdate AFTER UPDATE OF text ON transcriptSegment BEGIN INSERT INTO transcriptSearch(transcriptSearch, rowid, text) VALUES ('delete', old.rowid, old.text); INSERT INTO transcriptSearch(rowid, text) VALUES (new.rowid, new.text); END""",
            """CREATE TABLE "transcriptionJob" ("recordingId" TEXT PRIMARY KEY REFERENCES "recording"("id") ON DELETE CASCADE, "modelId" TEXT NOT NULL, "language" TEXT, "checkpoint" DOUBLE NOT NULL, "state" TEXT NOT NULL, "createdAt" DATETIME NOT NULL)""",
            """CREATE TABLE "roleSelection" ("role" TEXT PRIMARY KEY, "modelId" TEXT)""",
            """CREATE TABLE "modelRunStat" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "modelId" TEXT NOT NULL, "audioDuration" DOUBLE NOT NULL, "wallTime" DOUBLE NOT NULL, "outcome" TEXT NOT NULL, "date" DATETIME NOT NULL)""",
            """CREATE INDEX "modelRunStat_on_modelId" ON "modelRunStat"("modelId")""",
            """CREATE TABLE "networkLog" ("id" TEXT PRIMARY KEY, "host" TEXT NOT NULL, "modelId" TEXT NOT NULL, "bytes" INTEGER NOT NULL, "date" DATETIME NOT NULL)""",
        ),
        "v4-speakers" to listOf(
            """CREATE TABLE "person" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "createdAt" DATETIME NOT NULL)""",
            """CREATE TABLE "speaker" ("id" TEXT PRIMARY KEY, "recordingId" TEXT NOT NULL REFERENCES "recording"("id") ON DELETE CASCADE, "number" INTEGER NOT NULL, "name" TEXT, "personId" TEXT, "isSuggested" BOOLEAN NOT NULL, "embedding" BLOB, "talkTime" DOUBLE NOT NULL)""",
            """CREATE INDEX "speaker_on_recordingId" ON "speaker"("recordingId")""",
            """CREATE INDEX "speaker_on_personId" ON "speaker"("personId")""",
            """CREATE TABLE "voicePrint" ("personId" TEXT NOT NULL REFERENCES "person"("id") ON DELETE CASCADE, "modelId" TEXT NOT NULL, "embedding" BLOB NOT NULL, "talkTime" DOUBLE NOT NULL, PRIMARY KEY ("personId", "modelId"))""",
        ),
        "v5-summaries" to listOf(
            """CREATE TABLE "summary" ("id" TEXT PRIMARY KEY, "recordingId" TEXT NOT NULL REFERENCES "recording"("id") ON DELETE CASCADE, "templateName" TEXT NOT NULL, "modelId" TEXT NOT NULL, "language" TEXT, "sections" BLOB NOT NULL, "isComplete" BOOLEAN NOT NULL, "createdAt" DATETIME NOT NULL)""",
            """CREATE INDEX "summary_on_recordingId" ON "summary"("recordingId")""",
            """CREATE TABLE "summaryJob" ("summaryId" TEXT PRIMARY KEY REFERENCES "summary"("id") ON DELETE CASCADE, "payload" BLOB NOT NULL, "createdAt" DATETIME NOT NULL)""",
            """CREATE TABLE "summaryTemplate" ("id" TEXT PRIMARY KEY, "payload" BLOB NOT NULL)""",
        ),
        "v6-ask" to listOf(
            """CREATE TABLE "conversation" ("id" TEXT PRIMARY KEY, "title" TEXT NOT NULL, "scope" BLOB NOT NULL, "recordingId" TEXT REFERENCES "recording"("id") ON DELETE CASCADE, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL)""",
            """CREATE INDEX "conversation_on_recordingId" ON "conversation"("recordingId")""",
            """CREATE INDEX "conversation_on_updatedAt" ON "conversation"("updatedAt")""",
            """CREATE TABLE "chatMessage" ("id" TEXT PRIMARY KEY, "conversationId" TEXT NOT NULL REFERENCES "conversation"("id") ON DELETE CASCADE, "role" TEXT NOT NULL, "body" TEXT NOT NULL, "citations" BLOB NOT NULL, "state" TEXT NOT NULL, "createdAt" DATETIME NOT NULL)""",
            """CREATE INDEX "chatMessage_on_conversationId" ON "chatMessage"("conversationId")""",
            """CREATE TABLE "memory" ("id" TEXT PRIMARY KEY, "text" TEXT NOT NULL, "createdAt" DATETIME NOT NULL)""",
            """CREATE TABLE "knowledgeChunk" ("id" TEXT PRIMARY KEY, "recordingId" TEXT NOT NULL REFERENCES "recording"("id") ON DELETE CASCADE, "start" DOUBLE NOT NULL, "end" DOUBLE NOT NULL, "text" TEXT NOT NULL, "language" TEXT, "modelId" TEXT, "vector" BLOB)""",
            """CREATE INDEX "knowledgeChunk_on_recordingId" ON "knowledgeChunk"("recordingId")""",
            """CREATE INDEX "knowledgeChunk_on_modelId" ON "knowledgeChunk"("modelId")""",
            """CREATE TABLE "knowledgeIndex" ("recordingId" TEXT PRIMARY KEY REFERENCES "recording"("id") ON DELETE CASCADE, "sourceHash" TEXT NOT NULL, "modelId" TEXT)""",
            """CREATE VIRTUAL TABLE knowledgeSearch USING fts5(text, content='knowledgeChunk', content_rowid='rowid', tokenize='trigram')""",
            """CREATE TRIGGER knowledgeSearchInsert AFTER INSERT ON knowledgeChunk BEGIN INSERT INTO knowledgeSearch(rowid, text) VALUES (new.rowid, new.text); END""",
            """CREATE TRIGGER knowledgeSearchDelete AFTER DELETE ON knowledgeChunk BEGIN INSERT INTO knowledgeSearch(knowledgeSearch, rowid, text) VALUES ('delete', old.rowid, old.text); END""",
        ),
        "v7-transcript-versions" to listOf(
            """CREATE TABLE "transcriptVersion" ("id" TEXT PRIMARY KEY, "recordingId" TEXT NOT NULL REFERENCES "recording"("id") ON DELETE CASCADE, "modelId" TEXT NOT NULL, "language" TEXT, "savedAt" DOUBLE NOT NULL, "segments" BLOB NOT NULL)""",
            """CREATE INDEX "transcriptVersion_on_recordingId" ON "transcriptVersion"("recordingId")""",
        ),
    )

    val identifiers: List<String> get() = migrations.map { it.first }

    /** Applies what is missing. Returns false when the file comes from a newer app, which knows migrations this one does not. */
    fun migrate(sql: Sql): Boolean {
        sql.execute("""CREATE TABLE IF NOT EXISTS grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)""")
        val applied = sql.query("SELECT identifier FROM grdb_migrations") { it.string("identifier") }.toSet()
        if (applied.any { it !in identifiers }) return false
        for ((identifier, statements) in migrations) {
            if (identifier in applied) continue
            sql.transaction {
                statements.forEach { execute(it) }
                execute("INSERT INTO grdb_migrations (identifier) VALUES (?)", identifier)
            }
        }
        return true
    }
}
