package com.meetlaud.app.infra.persistence

import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import com.meetlaud.domain.ArchiveError
import com.meetlaud.domain.ArchiveException
import com.meetlaud.domain.AskScope
import com.meetlaud.domain.ChatMessage
import com.meetlaud.domain.ChatRole
import com.meetlaud.domain.AnswerState
import com.meetlaud.domain.Conversation
import com.meetlaud.domain.ConversationStore
import com.meetlaud.domain.DatabaseSnapshots
import com.meetlaud.domain.Folder
import com.meetlaud.domain.FolderID
import com.meetlaud.domain.JobState
import com.meetlaud.domain.KnowledgeChunk
import com.meetlaud.domain.KnowledgeIndexState
import com.meetlaud.domain.KnowledgeStore
import com.meetlaud.domain.Marker
import com.meetlaud.domain.MarkerKind
import com.meetlaud.domain.MemoryItem
import com.meetlaud.domain.ModelRole
import com.meetlaud.domain.ModelRunStat
import com.meetlaud.domain.ModelUsageStore
import com.meetlaud.domain.NetworkLogEntry
import com.meetlaud.domain.PauseReason
import com.meetlaud.domain.PauseSpan
import com.meetlaud.domain.Person
import com.meetlaud.domain.Recording
import com.meetlaud.domain.RecordingID
import com.meetlaud.domain.RecordingStatus
import com.meetlaud.domain.RecordingStore
import com.meetlaud.domain.SearchHit
import com.meetlaud.domain.SelectionMode
import com.meetlaud.domain.Speaker
import com.meetlaud.domain.SpeakerStore
import com.meetlaud.domain.Summary
import com.meetlaud.domain.SummaryJob
import com.meetlaud.domain.SummaryStore
import com.meetlaud.domain.SummaryTemplate
import com.meetlaud.domain.Transcript
import com.meetlaud.domain.TranscriptSegment
import com.meetlaud.domain.TranscriptStore
import com.meetlaud.domain.TranscriptVersion
import com.meetlaud.domain.TranscriptionJob
import com.meetlaud.domain.VoicePrint
import com.meetlaud.domain.localizedStandardCompare
import com.meetlaud.domain.uuidString
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Instant
import java.util.UUID

/**
 * SQLite storage, the same file the iOS app keeps (ios/Packages/Infrastructure/Persistence). One connection on its
 * own thread, in WAL, so that writes are never interleaved and a crash never leaves half a change.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class DatabaseStore(private val file: File) :
    RecordingStore, TranscriptStore, ModelUsageStore, SpeakerStore, SummaryStore, ConversationStore, KnowledgeStore, DatabaseSnapshots {

    private val lane = Dispatchers.IO.limitedParallelism(1)
    private val driver = BundledSQLiteDriver()
    private var sql: Sql = open(file)
    /** Fires after every write, so observers fetch again. GRDB's ValueObservation does the same on iOS. */
    private val changes = MutableSharedFlow<Unit>(extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)

    private fun open(file: File): Sql {
        val connection = driver.open(file.path)
        connection.execSQL("PRAGMA journal_mode = WAL")
        connection.execSQL("PRAGMA foreign_keys = ON")
        val sql = Sql(connection)
        check(Schema.migrate(sql)) { "The database comes from a newer version of the app" }
        return sql
    }

    private suspend fun <T> read(block: Sql.() -> T): T = withContext(lane) { sql.block() }

    private suspend fun <T> write(block: Sql.() -> T): T = withContext(lane) {
        val result = sql.transaction(block)
        changes.tryEmit(Unit)
        result
    }

    /** The value now, and again after every write. */
    private fun <T> observe(fetch: Sql.() -> T): Flow<T> = flow {
        emit(sql.fetch())
        changes.collect { emit(sql.fetch()) }
    }.flowOn(lane).distinctUntilChanged()

    private val RecordingID.key get() = rawValue.uuidString

    // MARK: - Recordings

    override suspend fun insert(recording: Recording) = write { insertRecording(recording) }

    private fun Sql.insertRecording(recording: Recording) = execute(
        """INSERT INTO recording (id, title, createdAt, duration, status, wasRecovered, folderId, deletedAt, attendees) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        recording.id.key, recording.title, recording.createdAt, recording.duration, recording.status.raw, recording.wasRecovered,
        recording.folderID?.rawValue?.uuidString, recording.deletedAt, SwiftCodable.encodeAttendees(recording.attendees),
    )

    override suspend fun update(recording: Recording) = write {
        execute(
            """UPDATE recording SET title = ?, createdAt = ?, duration = ?, status = ?, wasRecovered = ?, folderId = ?, deletedAt = ?, attendees = ? WHERE id = ?""",
            recording.title, recording.createdAt, recording.duration, recording.status.raw, recording.wasRecovered,
            recording.folderID?.rawValue?.uuidString, recording.deletedAt, SwiftCodable.encodeAttendees(recording.attendees), recording.id.key,
        )
    }

    override suspend fun delete(id: RecordingID) = write {
        // These answers quote the recording, and a deleted meeting must leave no words behind (D-053).
        execute("DELETE FROM chatMessage WHERE role = 'assistant' AND citations LIKE ?", "%${id.key}%")
        execute("DELETE FROM recording WHERE id = ?", id.key)
    }

    private fun recordingOf(row: Row): Recording? {
        val id = RecordingID.from(row.string("id")) ?: return null
        val status = RecordingStatus.from(row.string("status")) ?: return null
        return Recording(
            id = id, title = row.string("title"), createdAt = row.date("createdAt"), duration = row.double("duration"),
            status = status, wasRecovered = row.bool("wasRecovered"),
            folderID = row.optString("folderId")?.let { FolderID.from(it) }, deletedAt = row.optDate("deletedAt"),
            attendees = SwiftCodable.decodeAttendees(row.string("attendees")),
        )
    }

    override suspend fun recording(id: RecordingID): Recording? = read { one("SELECT * FROM recording WHERE id = ?", id.key, map = ::recordingOf) }

    override suspend fun recordings(status: RecordingStatus): List<Recording> =
        read { query("SELECT * FROM recording WHERE status = ?", status.raw, map = ::recordingOf) }

    override suspend fun insert(marker: Marker) = write {
        execute(
            "INSERT INTO marker (id, recordingId, time, kind, text, attachment) VALUES (?, ?, ?, ?, ?, ?)",
            marker.id.uuidString, marker.recordingID.key, marker.time, marker.kind.raw, marker.text, marker.attachment,
        )
    }

    override suspend fun markers(id: RecordingID): List<Marker> = read {
        query("SELECT * FROM marker WHERE recordingId = ? ORDER BY time", id.key) { row ->
            val kind = MarkerKind.from(row.string("kind")) ?: return@query null
            Marker(UUID.fromString(row.string("id")), id, row.double("time"), kind, row.optString("text"), row.optString("attachment"))
        }
    }

    override suspend fun insert(pause: PauseSpan) = write {
        execute(
            "INSERT INTO pauseSpan (recordingId, position, duration, reason) VALUES (?, ?, ?, ?)",
            pause.recordingID.key, pause.position, pause.duration, pause.reason.raw,
        )
    }

    override suspend fun pauses(id: RecordingID): List<PauseSpan> = read {
        query("SELECT * FROM pauseSpan WHERE recordingId = ? ORDER BY position", id.key) { row ->
            val reason = PauseReason.from(row.string("reason")) ?: return@query null
            PauseSpan(id, row.double("position"), row.double("duration"), reason)
        }
    }

    override suspend fun trashedRecordings(): List<Recording> =
        read { query("SELECT * FROM recording WHERE deletedAt IS NOT NULL ORDER BY deletedAt DESC", map = ::recordingOf) }

    override suspend fun search(query: String): List<SearchHit> = read {
        val pattern = "%" + escapeLike(query) + "%"
        val titles = query(
            "SELECT * FROM recording WHERE deletedAt IS NULL AND title LIKE ? ESCAPE '\\' ORDER BY createdAt DESC LIMIT 50", pattern,
        ) { recordingOf(it)?.let { recording -> SearchHit(recording = recording) } }
        val notes = query(
            """SELECT recording.*, marker.time AS hitTime, marker.text AS hitText FROM marker JOIN recording ON recording.id = marker.recordingId
               WHERE recording.deletedAt IS NULL AND marker.text LIKE ? ESCAPE '\' ORDER BY recording.createdAt DESC, marker.time LIMIT 50""",
            pattern,
        ) { row -> recordingOf(row)?.let { SearchHit(recording = it, time = row.optDouble("hitTime"), excerpt = row.optString("hitText")) } }
        titles + notes + searchTranscripts(query, pattern)
    }

    private fun Sql.searchTranscripts(query: String, pattern: String): List<SearchHit> {
        val columns = "recording.*, transcriptSegment.start AS hitTime, transcriptSegment.text AS hitText"
        val map = { row: Row -> recordingOf(row)?.let { SearchHit(recording = it, time = row.optDouble("hitTime"), excerpt = row.optString("hitText")) } }
        return if (query.codePointCount(0, query.length) >= 3) {
            val phrase = "\"" + query.replace("\"", "\"\"") + "\""
            query(
                """SELECT $columns FROM transcriptSearch JOIN transcriptSegment ON transcriptSegment.rowid = transcriptSearch.rowid
                   JOIN recording ON recording.id = transcriptSegment.recordingId WHERE transcriptSearch MATCH ? AND recording.deletedAt IS NULL
                   ORDER BY recording.createdAt DESC, transcriptSegment.start LIMIT 50""",
                phrase, map = map,
            )
        } else {
            query(
                """SELECT $columns FROM transcriptSegment JOIN recording ON recording.id = transcriptSegment.recordingId
                   WHERE transcriptSegment.text LIKE ? ESCAPE '\' AND recording.deletedAt IS NULL
                   ORDER BY recording.createdAt DESC, transcriptSegment.start LIMIT 50""",
                pattern, map = map,
            )
        }
    }

    /** Search text comes from the person, and `%` or `_` must not act as wildcards. */
    private fun escapeLike(text: String) = text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")

    /** Every recording now, for a one-off look such as the showcase seed. */
    suspend fun observeRecordingsOnce(): List<Recording> = read { query("SELECT * FROM recording", map = ::recordingOf) }

    override fun observeRecordings(): Flow<List<Recording>> = observe { query("SELECT * FROM recording ORDER BY createdAt DESC", map = ::recordingOf) }

    override suspend fun insert(folder: Folder) = write {
        execute("INSERT INTO folder (id, name, createdAt) VALUES (?, ?, ?)", folder.id.rawValue.uuidString, folder.name, folder.createdAt)
    }

    override suspend fun update(folder: Folder) = write {
        execute("UPDATE folder SET name = ?, createdAt = ? WHERE id = ?", folder.name, folder.createdAt, folder.id.rawValue.uuidString)
    }

    override suspend fun deleteFolder(id: FolderID) = write { execute("DELETE FROM folder WHERE id = ?", id.rawValue.uuidString) }

    override fun observeFolders(): Flow<List<Folder>> = observe {
        query("SELECT * FROM folder ORDER BY createdAt") { row ->
            FolderID.from(row.string("id"))?.let { Folder(it, row.string("name"), row.date("createdAt")) }
        }
    }

    // MARK: - Transcripts

    override suspend fun transcript(id: RecordingID): Transcript? = read {
        one("SELECT * FROM transcript WHERE recordingId = ?", id.key) { Transcript(id, it.string("modelId"), it.optString("language"), it.bool("isComplete")) }
    }

    override suspend fun save(transcript: Transcript) = write {
        execute(
            "INSERT OR REPLACE INTO transcript (recordingId, modelId, language, isComplete) VALUES (?, ?, ?, ?)",
            transcript.recordingID.key, transcript.modelID, transcript.language, transcript.isComplete,
        )
    }

    override suspend fun segments(id: RecordingID): List<TranscriptSegment> = read {
        query("SELECT * FROM transcriptSegment WHERE recordingId = ? ORDER BY start", id.key) { row ->
            TranscriptSegment(UUID.fromString(row.string("id")), id, row.double("start"), row.double("end"), row.string("text"), row.optString("speaker"))
        }
    }

    override suspend fun append(segments: List<TranscriptSegment>, job: TranscriptionJob) = write {
        for (segment in segments) {
            execute(
                "INSERT INTO transcriptSegment (id, recordingId, start, end, text, speaker) VALUES (?, ?, ?, ?, ?, ?)",
                segment.id.uuidString, segment.recordingID.key, segment.start, segment.end, segment.text, segment.speaker,
            )
        }
        writeJob(job)
    }

    override suspend fun update(segment: TranscriptSegment) = write {
        execute("UPDATE transcriptSegment SET text = ?, speaker = ? WHERE id = ?", segment.text, segment.speaker, segment.id.uuidString)
    }

    override suspend fun replaceAll(id: RecordingID, text: String, replacement: String): Int {
        if (text.isEmpty()) return 0
        return write {
            var count = 0
            for ((rowID, original) in query("SELECT id, text FROM transcriptSegment WHERE recordingId = ?", id.key) { it.string("id") to it.string("text") }) {
                val updated = original.replace(text, replacement)
                if (updated != original) {
                    execute("UPDATE transcriptSegment SET text = ? WHERE id = ?", updated, rowID)
                    count += 1
                }
            }
            for ((rowID, original) in query("SELECT id, name FROM speaker WHERE recordingId = ? AND name IS NOT NULL", id.key) { it.string("id") to it.string("name") }) {
                val updated = original.replace(text, replacement)
                if (updated != original) {
                    execute("UPDATE speaker SET name = ? WHERE id = ?", updated, rowID)
                    count += 1
                }
            }
            count
        }
    }

    override suspend fun deleteTranscript(id: RecordingID) = write {
        execute("DELETE FROM transcriptSegment WHERE recordingId = ?", id.key)
        execute("DELETE FROM transcript WHERE recordingId = ?", id.key)
    }

    override suspend fun versions(id: RecordingID): List<TranscriptVersion> = read {
        query("SELECT * FROM transcriptVersion WHERE recordingId = ? ORDER BY savedAt DESC", id.key) { row ->
            val stored = SwiftCodable.decodeStoredSegments(row.blob("segments")) ?: return@query null
            TranscriptVersion(
                UUID.fromString(row.string("id")), id, row.string("modelId"), row.optString("language"),
                Instant.ofEpochMilli(Math.round(row.double("savedAt") * 1000)),
                stored.map { TranscriptSegment(recordingID = id, start = it.first, end = it.second, text = it.third) },
            )
        }
    }

    override suspend fun save(version: TranscriptVersion) = write {
        val key = version.recordingID.key
        execute(
            "INSERT INTO transcriptVersion (id, recordingId, modelId, language, savedAt, segments) VALUES (?, ?, ?, ?, ?, ?)",
            version.id.uuidString, key, version.modelID, version.language, version.savedAt.toEpochMilli() / 1000.0,
            SwiftCodable.encodeStoredSegments(version.segments.map { Triple(it.start, it.end, it.text) }),
        )
        execute(
            "DELETE FROM transcriptVersion WHERE recordingId = ? AND id NOT IN (SELECT id FROM transcriptVersion WHERE recordingId = ? ORDER BY savedAt DESC LIMIT ?)",
            key, key, TranscriptVersion.LIMIT,
        )
    }

    override suspend fun deleteVersion(id: UUID) = write { execute("DELETE FROM transcriptVersion WHERE id = ?", id.uuidString) }

    private fun Sql.writeJob(job: TranscriptionJob) = execute(
        """INSERT INTO transcriptionJob (recordingId, modelId, language, checkpoint, state, createdAt) VALUES (?, ?, ?, ?, ?, ?)
           ON CONFLICT(recordingId) DO UPDATE SET language = excluded.language, checkpoint = excluded.checkpoint, state = excluded.state""",
        job.recordingID.key, job.modelID, job.language, job.checkpoint, job.state.raw, Instant.now(),
    )

    private fun jobOf(row: Row): TranscriptionJob? {
        val id = RecordingID.from(row.string("recordingId")) ?: return null
        val state = JobState.from(row.string("state")) ?: return null
        return TranscriptionJob(id, row.string("modelId"), row.optString("language"), row.double("checkpoint"), state)
    }

    override suspend fun job(id: RecordingID): TranscriptionJob? = read { one("SELECT * FROM transcriptionJob WHERE recordingId = ?", id.key, map = ::jobOf) }

    override suspend fun jobs(): List<TranscriptionJob> = read { query("SELECT * FROM transcriptionJob ORDER BY createdAt", map = ::jobOf) }

    override suspend fun save(job: TranscriptionJob) = write { writeJob(job) }

    override suspend fun deleteJob(id: RecordingID) = write { execute("DELETE FROM transcriptionJob WHERE recordingId = ?", id.key) }

    // MARK: - Models

    override suspend fun selection(role: ModelRole): SelectionMode = read {
        one("SELECT modelId FROM roleSelection WHERE role = ?", role.raw) { it.optString("modelId") }
            ?.let { SelectionMode.Pinned(it) } ?: SelectionMode.Automatic
    }

    override suspend fun setSelection(mode: SelectionMode, role: ModelRole) = write {
        when (mode) {
            SelectionMode.Automatic -> execute("DELETE FROM roleSelection WHERE role = ?", role.raw)
            is SelectionMode.Pinned -> execute("INSERT OR REPLACE INTO roleSelection (role, modelId) VALUES (?, ?)", role.raw, mode.id)
        }
    }

    override suspend fun insert(stat: ModelRunStat) = write {
        execute(
            "INSERT INTO modelRunStat (modelId, audioDuration, wallTime, outcome, date) VALUES (?, ?, ?, ?, ?)",
            stat.modelID, stat.audioDuration, stat.wallTime, stat.outcome.raw, stat.date,
        )
    }

    override suspend fun stats(): List<ModelRunStat> = read {
        query("SELECT * FROM modelRunStat ORDER BY date DESC LIMIT 500") { row ->
            val outcome = ModelRunStat.Outcome.entries.firstOrNull { it.raw == row.string("outcome") } ?: return@query null
            ModelRunStat(row.string("modelId"), row.double("audioDuration"), row.double("wallTime"), outcome, row.date("date"))
        }
    }

    override suspend fun logNetwork(entry: NetworkLogEntry) = write {
        execute("INSERT INTO networkLog (id, host, modelId, bytes, date) VALUES (?, ?, ?, ?, ?)", entry.id.uuidString, entry.host, entry.modelID, entry.bytes, entry.date)
    }

    override suspend fun clearNetworkLog() = write { execute("DELETE FROM networkLog") }

    override suspend fun networkLog(): List<NetworkLogEntry> = read {
        query("SELECT * FROM networkLog ORDER BY date DESC") { row ->
            NetworkLogEntry(UUID.fromString(row.string("id")), row.string("host"), row.string("modelId"), row.long("bytes"), row.date("date"))
        }
    }

    // MARK: - Speakers

    private fun speakerOf(row: Row, id: RecordingID) = Speaker(
        UUID.fromString(row.string("id")), id, row.int("number"), row.optString("name"),
        row.optString("personId")?.let { runCatching { UUID.fromString(it) }.getOrNull() }, row.bool("isSuggested"),
        Vectors.decode(row.optBlob("embedding")), row.double("talkTime"),
    )

    override suspend fun speakers(id: RecordingID): List<Speaker> = read {
        query("SELECT * FROM speaker WHERE recordingId = ? ORDER BY number", id.key) { speakerOf(it, id) }
    }

    override suspend fun saveSpeakers(speakers: List<Speaker>, assignments: Map<UUID, UUID>, id: RecordingID) = write {
        execute("UPDATE transcriptSegment SET speaker = NULL WHERE recordingId = ?", id.key)
        execute("DELETE FROM speaker WHERE recordingId = ?", id.key)
        for (speaker in speakers) {
            execute(
                "INSERT INTO speaker (id, recordingId, number, name, personId, isSuggested, embedding, talkTime) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                speaker.id.uuidString, speaker.recordingID.key, speaker.number, speaker.name, speaker.personID?.uuidString,
                speaker.isSuggested, Vectors.encode(speaker.embedding), speaker.talkTime,
            )
        }
        for ((segment, speaker) in assignments) {
            execute("UPDATE transcriptSegment SET speaker = ? WHERE id = ?", speaker.uuidString, segment.uuidString)
        }
    }

    override suspend fun update(speaker: Speaker) = write {
        execute("UPDATE speaker SET name = ?, personId = ?, isSuggested = ? WHERE id = ?", speaker.name, speaker.personID?.uuidString, speaker.isSuggested, speaker.id.uuidString)
    }

    override suspend fun setSpeaker(speakerID: UUID, segmentID: UUID) = write {
        execute("UPDATE transcriptSegment SET speaker = ? WHERE id = ?", speakerID.uuidString, segmentID.uuidString)
    }

    override suspend fun merge(source: UUID, target: UUID) = write {
        execute("UPDATE transcriptSegment SET speaker = ? WHERE speaker = ?", target.uuidString, source.uuidString)
        execute("DELETE FROM speaker WHERE id = ?", source.uuidString)
    }

    override suspend fun people(): List<Person> = read {
        query("SELECT * FROM person ORDER BY name COLLATE NOCASE") { Person(UUID.fromString(it.string("id")), it.string("name"), it.date("createdAt")) }
    }

    override suspend fun insert(person: Person) = write {
        execute("INSERT INTO person (id, name, createdAt) VALUES (?, ?, ?)", person.id.uuidString, person.name, person.createdAt)
    }

    override suspend fun update(person: Person) = write {
        execute("UPDATE person SET name = ? WHERE id = ?", person.name, person.id.uuidString)
        execute("UPDATE speaker SET name = ? WHERE personId = ?", person.name, person.id.uuidString)
    }

    override suspend fun deletePerson(id: UUID) = write {
        // Voice prints go through the foreign key. Names in old transcripts stay, and stop being linked.
        execute("UPDATE speaker SET personId = NULL WHERE personId = ?", id.uuidString)
        execute("DELETE FROM person WHERE id = ?", id.uuidString)
    }

    override suspend fun mergePerson(source: UUID, target: Person) = write {
        execute("UPDATE speaker SET personId = ?, name = ? WHERE personId = ?", target.id.uuidString, target.name, source.uuidString)
        execute("UPDATE OR IGNORE voicePrint SET personId = ? WHERE personId = ?", target.id.uuidString, source.uuidString)
        // Any voice print left here lost to the target's, and goes with the person through the foreign key.
        execute("DELETE FROM person WHERE id = ?", source.uuidString)
    }

    override suspend fun voicePrints(modelID: String): List<VoicePrint> = read {
        query("SELECT * FROM voicePrint WHERE modelId = ?", modelID) {
            VoicePrint(UUID.fromString(it.string("personId")), modelID, Vectors.decode(it.blob("embedding")), it.double("talkTime"))
        }
    }

    override suspend fun save(print: VoicePrint) = write {
        execute(
            "INSERT OR REPLACE INTO voicePrint (personId, modelId, embedding, talkTime) VALUES (?, ?, ?, ?)",
            print.personID.uuidString, print.modelID, Vectors.encode(print.embedding), print.talkTime,
        )
    }

    override suspend fun recordings(person: UUID): List<RecordingID> = read {
        query("SELECT DISTINCT recordingId FROM speaker WHERE personId = ?", person.uuidString) { RecordingID.from(it.string("recordingId")) }
    }

    // MARK: - Summaries

    private fun summaryOf(row: Row, id: RecordingID): Summary? {
        val sections = SwiftCodable.decodeSections(row.blob("sections")) ?: return null
        return Summary(
            UUID.fromString(row.string("id")), id, row.string("templateName"), row.string("modelId"), row.optString("language"),
            sections, row.bool("isComplete"), row.date("createdAt"),
        )
    }

    private fun Sql.writeSummary(summary: Summary) = execute(
        // `OR REPLACE` deletes the row first, and the cascade would take the job with it.
        """INSERT INTO summary (id, recordingId, templateName, modelId, language, sections, isComplete, createdAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT (id) DO UPDATE SET sections = excluded.sections, isComplete = excluded.isComplete""",
        summary.id.uuidString, summary.recordingID.key, summary.templateName, summary.modelID, summary.language,
        SwiftCodable.encodeSections(summary.sections), summary.isComplete, summary.createdAt,
    )

    private fun Sql.writeSummaryJob(job: SummaryJob) = execute(
        // Updates in place: `OR REPLACE` would move the job to the back of the queue.
        "INSERT INTO summaryJob (summaryId, payload, createdAt) VALUES (?, ?, ?) ON CONFLICT (summaryId) DO UPDATE SET payload = excluded.payload",
        job.summaryID.uuidString, SwiftCodable.encodeJob(job), Instant.now(),
    )

    override suspend fun summaries(id: RecordingID): List<Summary> = read {
        query("SELECT * FROM summary WHERE recordingId = ? ORDER BY createdAt", id.key) { summaryOf(it, id) }
    }

    override suspend fun save(summary: Summary) = write { writeSummary(summary) }

    override suspend fun save(summary: Summary, job: SummaryJob) = write {
        writeSummary(summary)
        writeSummaryJob(job)
    }

    override suspend fun complete(summary: Summary) = write {
        writeSummary(summary.copy(isComplete = true))
        execute("DELETE FROM summaryJob WHERE summaryId = ?", summary.id.uuidString)
    }

    override suspend fun deleteSummary(id: UUID) = write { execute("DELETE FROM summary WHERE id = ?", id.uuidString) }

    override suspend fun summaryJobs(): List<SummaryJob> = read {
        query("SELECT payload FROM summaryJob ORDER BY createdAt, summaryId") { SwiftCodable.decodeJob(it.blob("payload")) }
    }

    override suspend fun save(job: SummaryJob) = write { writeSummaryJob(job) }

    override suspend fun deleteSummaryJob(summaryID: UUID) = write { execute("DELETE FROM summaryJob WHERE summaryId = ?", summaryID.uuidString) }

    override suspend fun userTemplates(): List<SummaryTemplate> = read {
        query("SELECT payload FROM summaryTemplate") { SwiftCodable.decodeTemplate(it.blob("payload")) }
            .sortedWith { a, b -> localizedStandardCompare(a.name, b.name) }
    }

    override suspend fun save(template: SummaryTemplate) = write {
        execute("INSERT OR REPLACE INTO summaryTemplate (id, payload) VALUES (?, ?)", template.id, SwiftCodable.encodeTemplate(template))
    }

    override suspend fun deleteTemplate(id: String) = write { execute("DELETE FROM summaryTemplate WHERE id = ?", id) }

    // MARK: - Ask

    override suspend fun conversations(): List<Conversation> = read {
        query("SELECT * FROM conversation ORDER BY updatedAt DESC") { row ->
            val scope = SwiftCodable.decodeScope(row.blob("scope")) ?: return@query null
            Conversation(UUID.fromString(row.string("id")), row.string("title"), scope, row.date("createdAt"), row.date("updatedAt"))
        }
    }

    override suspend fun save(conversation: Conversation) = write {
        // `OR REPLACE` deletes the row first, and the cascade would take every message with it.
        execute(
            """INSERT INTO conversation (id, title, scope, recordingId, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?)
               ON CONFLICT (id) DO UPDATE SET title = excluded.title, scope = excluded.scope, recordingId = excluded.recordingId, updatedAt = excluded.updatedAt""",
            conversation.id.uuidString, conversation.title, SwiftCodable.encodeScope(conversation.scope),
            conversation.scope.recordingID?.key, conversation.createdAt, conversation.updatedAt,
        )
    }

    override suspend fun deleteConversation(id: UUID) = write { execute("DELETE FROM conversation WHERE id = ?", id.uuidString) }

    override suspend fun messages(conversation: UUID): List<ChatMessage> = read {
        query("SELECT * FROM chatMessage WHERE conversationId = ? ORDER BY createdAt, role DESC", conversation.uuidString) { row ->
            val role = ChatRole.from(row.string("role")) ?: return@query null
            val state = AnswerState.from(row.string("state")) ?: return@query null
            val citations = SwiftCodable.decodeCitations(row.blob("citations")) ?: return@query null
            ChatMessage(UUID.fromString(row.string("id")), conversation, role, row.string("body"), citations, state, row.date("createdAt"))
        }
    }

    override suspend fun save(message: ChatMessage) = write {
        execute(
            "INSERT OR REPLACE INTO chatMessage (id, conversationId, role, body, citations, state, createdAt) VALUES (?, ?, ?, ?, ?, ?, ?)",
            message.id.uuidString, message.conversationID.uuidString, message.role.raw, message.body,
            SwiftCodable.encodeCitations(message.citations), message.state.raw, message.createdAt,
        )
    }

    override suspend fun memories(): List<MemoryItem> = read {
        query("SELECT * FROM memory ORDER BY createdAt") { MemoryItem(UUID.fromString(it.string("id")), it.string("text"), it.date("createdAt")) }
    }

    override suspend fun save(memory: MemoryItem) = write {
        execute("INSERT OR REPLACE INTO memory (id, text, createdAt) VALUES (?, ?, ?)", memory.id.uuidString, memory.text, memory.createdAt)
    }

    override suspend fun deleteMemory(id: UUID) = write { execute("DELETE FROM memory WHERE id = ?", id.uuidString) }

    // MARK: - Knowledge

    /** The part of a query that keeps it inside the scope and out of the trash. */
    private fun filter(scope: AskScope): Pair<String, List<Any?>> = when (scope) {
        AskScope.Library -> "recording.deletedAt IS NULL" to emptyList()
        is AskScope.Folder -> "recording.deletedAt IS NULL AND recording.folderId = ?" to listOf(scope.id.rawValue.uuidString)
        is AskScope.Recording -> "recording.deletedAt IS NULL AND recording.id = ?" to listOf(scope.id.key)
    }

    private fun chunkOf(row: Row): KnowledgeChunk? {
        val recording = RecordingID.from(row.string("recordingId")) ?: return null
        return KnowledgeChunk(
            UUID.fromString(row.string("id")), recording, row.double("start"), row.double("end"), row.string("text"),
            row.optString("language"), row.optString("modelId"), row.optBlob("vector")?.let { Vectors.decode(it) },
        )
    }

    override suspend fun indexStates(): Map<RecordingID, KnowledgeIndexState> = read {
        query("SELECT * FROM knowledgeIndex") { row ->
            RecordingID.from(row.string("recordingId"))?.let { it to KnowledgeIndexState(row.string("sourceHash"), row.optString("modelId")) }
        }.toMap()
    }

    override suspend fun replaceChunks(chunks: List<KnowledgeChunk>, id: RecordingID, state: KnowledgeIndexState) = write {
        execute("DELETE FROM knowledgeChunk WHERE recordingId = ?", id.key)
        for (chunk in chunks) {
            execute(
                "INSERT INTO knowledgeChunk (id, recordingId, start, end, text, language, modelId, vector) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                chunk.id.uuidString, id.key, chunk.start, chunk.end, chunk.text, chunk.language, chunk.modelID, chunk.vector?.let { Vectors.encode(it) },
            )
        }
        execute("INSERT OR REPLACE INTO knowledgeIndex (recordingId, sourceHash, modelId) VALUES (?, ?, ?)", id.key, state.sourceHash, state.modelID)
    }

    override suspend fun removeChunks(id: RecordingID) = write {
        execute("DELETE FROM knowledgeChunk WHERE recordingId = ?", id.key)
        execute("DELETE FROM knowledgeIndex WHERE recordingId = ?", id.key)
    }

    override suspend fun lexicalMatches(terms: List<String>, scope: AskScope, limit: Int): List<UUID> = read {
        val long = terms.filter { it.codePointCount(0, it.length) >= 3 }
        val short = terms.filter { it.codePointCount(0, it.length) < 3 }
        val (where, arguments) = filter(scope)
        val found = mutableListOf<String>()
        if (long.isNotEmpty()) {
            val match = long.joinToString(" OR ") { "\"" + it.replace("\"", "\"\"") + "\"" }
            found += query(
                """SELECT knowledgeChunk.id FROM knowledgeSearch JOIN knowledgeChunk ON knowledgeChunk.rowid = knowledgeSearch.rowid
                   JOIN recording ON recording.id = knowledgeChunk.recordingId WHERE knowledgeSearch MATCH ? AND $where
                   ORDER BY bm25(knowledgeSearch) LIMIT ?""",
                *(listOf<Any?>(match) + arguments + limit).toTypedArray(),
            ) { it.string("id") }
        }
        // Trigrams cannot see two characters, and two Japanese characters are often the word that matters.
        for (term in short) {
            found += query(
                """SELECT knowledgeChunk.id FROM knowledgeChunk JOIN recording ON recording.id = knowledgeChunk.recordingId
                   WHERE knowledgeChunk.text LIKE ? ESCAPE '\' AND $where LIMIT ?""",
                *(listOf<Any?>("%" + escapeLike(term) + "%") + arguments + limit).toTypedArray(),
            ) { it.string("id") }
        }
        found.mapNotNull { runCatching { UUID.fromString(it) }.getOrNull() }
    }

    override suspend fun nearest(vector: List<Float>, modelID: String, scope: AskScope, limit: Int): List<UUID> = read {
        val (where, arguments) = filter(scope)
        val expected = vector.size * 4
        val target = vector.toFloatArray()
        val best = ArrayList<Pair<String, Float>>()
        // One row at a time. Holding every vector of a large library at once is how an app gets killed.
        query(
            """SELECT knowledgeChunk.id AS id, knowledgeChunk.vector AS vector FROM knowledgeChunk JOIN recording ON recording.id = knowledgeChunk.recordingId
               WHERE knowledgeChunk.modelId = ? AND knowledgeChunk.vector IS NOT NULL AND $where""",
            *(listOf<Any?>(modelID) + arguments).toTypedArray(),
        ) { row ->
            val data = row.blob("vector")
            if (data.size != expected) return@query null
            val buffer = java.nio.ByteBuffer.wrap(data).order(java.nio.ByteOrder.LITTLE_ENDIAN)
            var score = 0f
            for (index in target.indices) score += target[index] * buffer.getFloat()
            if (best.size < limit || score > (best.lastOrNull()?.second ?: -1f)) {
                val position = best.indexOfFirst { it.second < score }.let { if (it < 0) best.size else it }
                best.add(position, row.string("id") to score)
                if (best.size > limit) best.removeAt(best.lastIndex)
            }
            null
        }
        best.mapNotNull { runCatching { UUID.fromString(it.first) }.getOrNull() }
    }

    override suspend fun chunks(ids: List<UUID>): List<KnowledgeChunk> {
        if (ids.isEmpty()) return emptyList()
        return read {
            query("SELECT * FROM knowledgeChunk WHERE id IN (${ids.joinToString(",") { "?" }})", *ids.map { it.uuidString }.toTypedArray(), map = ::chunkOf)
        }
    }

    // MARK: - Snapshots

    override suspend fun writeSnapshot(file: File, includingVoicePrints: Boolean): Unit = withContext(lane) {
        file.delete()
        sql.execute("VACUUM INTO ?", file.path)
        if (!includingVoicePrints) {
            val copy = Sql(driver.open(file.path))
            try {
                copy.transaction {
                    execute("DELETE FROM voicePrint")
                    // A speaker's embedding identifies a voice just as much as a saved voice print does (D-064).
                    execute("UPDATE speaker SET embedding = NULL")
                }
                // Freed pages keep their old contents until this rewrites the file.
                copy.execute("VACUUM")
            } finally {
                copy.connection.close()
            }
        }
    }

    override suspend fun restoreSnapshot(file: File): Unit = withContext(lane) {
        // An archive from an older version catches up here, before it touches the live data.
        val source = runCatching { Sql(driver.open(file.path)) }.getOrElse { throw ArchiveException(ArchiveError.DAMAGED) }
        try {
            val current = runCatching {
                source.execute("PRAGMA foreign_keys = ON")
                Schema.migrate(source)
            }.getOrElse { throw ArchiveException(ArchiveError.DAMAGED) }
            if (!current) throw ArchiveException(ArchiveError.INCOMPATIBLE)
        } finally {
            source.connection.close()
        }
        // The live file is replaced only after the copy reads and migrates correctly.
        sql.connection.close()
        val live = this@DatabaseStore.file
        listOf("-wal", "-shm").forEach { File(live.path + it).delete() }
        file.copyTo(live, overwrite = true)
        sql = open(live)
        changes.tryEmit(Unit)
        Unit
    }

    override suspend fun eraseEverything(): Unit = withContext(lane) {
        sql.execute("PRAGMA secure_delete = ON")
        sql.transaction {
            // Cascades and search triggers take care of everything hanging from these.
            for (table in listOf("recording", "folder", "person", "conversation", "memory", "summaryTemplate", "roleSelection", "modelRunStat", "networkLog")) {
                execute("DELETE FROM $table")
            }
        }
        sql.execute("VACUUM")
        changes.tryEmit(Unit)
        Unit
    }
}
