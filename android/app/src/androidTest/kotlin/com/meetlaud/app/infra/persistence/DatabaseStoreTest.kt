package com.meetlaud.app.infra.persistence

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.meetlaud.domain.AskScope
import com.meetlaud.domain.ChatMessage
import com.meetlaud.domain.ChatRole
import com.meetlaud.domain.Citation
import com.meetlaud.domain.Conversation
import com.meetlaud.domain.Folder
import com.meetlaud.domain.KnowledgeChunk
import com.meetlaud.domain.KnowledgeIndexState
import com.meetlaud.domain.Marker
import com.meetlaud.domain.MarkerKind
import com.meetlaud.domain.Recording
import com.meetlaud.domain.RecordingStatus
import com.meetlaud.domain.SectionKind
import com.meetlaud.domain.Speaker
import com.meetlaud.domain.Summary
import com.meetlaud.domain.SummaryItem
import com.meetlaud.domain.SummarySection
import com.meetlaud.domain.TranscriptSegment
import com.meetlaud.domain.TranscriptionJob
import com.meetlaud.domain.uuidString
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.time.Instant

/** The store on a real phone, with the SQLite that ships in the app: FTS5 trigram search, cascades, snapshots. */
@RunWith(AndroidJUnit4::class)
class DatabaseStoreTest {
    private lateinit var folder: File
    private lateinit var store: DatabaseStore

    @Before
    fun open() {
        folder = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir, "db-test-${System.nanoTime()}").apply { mkdirs() }
        store = DatabaseStore(File(folder, "meetlaud.sqlite"))
    }

    @After
    fun close() {
        folder.deleteRecursively()
    }

    private val now = Instant.parse("2026-11-08T08:57:00.123Z")

    @Test
    fun aRecordingRoundTripsWithEveryField() = runBlocking {
        val group = Folder(name = "Marketing", createdAt = now)
        store.insert(group)
        val recording = Recording(title = "Spring campaign", createdAt = now, duration = 2880.5, status = RecordingStatus.CAPTURING, folderID = group.id, attendees = listOf("Ana", "Kenji"))
        store.insert(recording)
        assertEquals(recording, store.recording(recording.id))
        assertEquals(listOf(recording), store.recordings(RecordingStatus.CAPTURING))
        assertEquals(listOf(recording), store.observeRecordings().first())
    }

    @Test
    fun japaneseFindsItsTranscriptThroughTrigramsAndShortWordsThroughLike() = runBlocking {
        val recording = Recording(title = "定例会議", createdAt = now, duration = 60.0)
        store.insert(recording)
        val segments = listOf(
            TranscriptSegment(recordingID = recording.id, start = 0.0, end = 5.0, text = "予算は動画に移します。"),
            TranscriptSegment(recordingID = recording.id, start = 5.0, end = 9.0, text = "The print ads are gone."),
        )
        store.append(segments, TranscriptionJob(recording.id, "m", "ja", checkpoint = 9.0))
        assertEquals(9.0, store.job(recording.id)?.checkpoint)
        assertTrue(store.search("動画に移").any { it.time == 0.0 })
        assertTrue(store.search("予算").any { it.time == 0.0 })
        assertTrue(store.search("print ads").any { it.time == 5.0 })
        assertTrue(store.search("%").none { it.time != null })
    }

    @Test
    fun deletingARecordingRemovesWhatHangsFromItAndTheAnswersThatQuoteIt() = runBlocking {
        val recording = Recording(title = "Budget", createdAt = now, duration = 60.0)
        store.insert(recording)
        store.insert(Marker(recordingID = recording.id, time = 3.0, kind = MarkerKind.NOTE, text = "Budget agreed"))
        val conversation = Conversation(scope = AskScope.Library, createdAt = now)
        store.save(conversation)
        val citation = Citation(1, recording.id, "Budget", 3.0, "Budget agreed")
        store.save(ChatMessage(conversationID = conversation.id, role = ChatRole.ASSISTANT, body = "Yes [1].", citations = listOf(citation), createdAt = now))
        assertEquals(listOf(citation), store.messages(conversation.id).single().citations)
        store.delete(recording.id)
        assertNull(store.recording(recording.id))
        assertTrue(store.markers(recording.id).isEmpty())
        assertTrue(store.messages(conversation.id).isEmpty())
    }

    @Test
    fun speakersSummariesAndScopesKeepTheirShape() = runBlocking {
        val recording = Recording(title = "Sync", createdAt = now, duration = 60.0)
        store.insert(recording)
        val speaker = Speaker(recordingID = recording.id, number = 1, name = "Ana", embedding = listOf(0.25f, -1.5f), talkTime = 12.0)
        val segment = TranscriptSegment(recordingID = recording.id, start = 0.0, end = 2.0, text = "Hi")
        store.append(listOf(segment), TranscriptionJob(recording.id, "m", null))
        store.saveSpeakers(listOf(speaker), mapOf(segment.id to speaker.id), recording.id)
        assertEquals(listOf(speaker), store.speakers(recording.id))
        assertEquals(speaker.id.uuidString, store.segments(recording.id).single().speaker)

        val summary = Summary(
            recordingID = recording.id, templateName = "Summary", modelID = "m", language = "en", createdAt = now,
            sections = listOf(SummarySection("Action items", SectionKind.TASKS, listOf(SummaryItem(text = "Send it", sourceTime = 66.0, owner = "Ana", due = "Friday")))),
        )
        store.save(summary)
        assertEquals(listOf(summary), store.summaries(recording.id))

        val scoped = Conversation(scope = AskScope.Recording(recording.id), createdAt = now)
        store.save(scoped)
        assertEquals(AskScope.Recording(recording.id), store.conversations().single().scope)
    }

    @Test
    fun searchByMeaningAndByWordsStaysInsideItsScope() = runBlocking {
        val inside = Recording(title = "A", createdAt = now, duration = 60.0)
        val trashed = Recording(title = "B", createdAt = now, duration = 60.0, deletedAt = now)
        store.insert(inside)
        store.insert(trashed)
        val near = KnowledgeChunk(recordingID = inside.id, start = 0.0, end = 5.0, text = "the video budget doubles", modelID = "e", vector = listOf(1f, 0f))
        val far = KnowledgeChunk(recordingID = inside.id, start = 5.0, end = 9.0, text = "lunch plans", modelID = "e", vector = listOf(0f, 1f))
        val hidden = KnowledgeChunk(recordingID = trashed.id, start = 0.0, end = 5.0, text = "the video budget doubles", modelID = "e", vector = listOf(1f, 0f))
        store.replaceChunks(listOf(near, far), inside.id, KnowledgeIndexState("h", "e"))
        store.replaceChunks(listOf(hidden), trashed.id, KnowledgeIndexState("h", "e"))
        assertEquals(listOf(near.id, far.id), store.nearest(listOf(1f, 0f), "e", AskScope.Library, 5))
        assertEquals(listOf(near.id), store.lexicalMatches(listOf("budget"), AskScope.Library, 5))
        assertEquals(listOf(near.id), store.lexicalMatches(listOf("vi"), AskScope.Recording(inside.id), 5))
    }

    @Test
    fun aSnapshotRestoresAndCanLeaveVoicesOut() = runBlocking {
        val recording = Recording(title = "Kept", createdAt = now, duration = 60.0)
        store.insert(recording)
        store.saveSpeakers(listOf(Speaker(recordingID = recording.id, number = 1, embedding = listOf(1f))), emptyMap(), recording.id)
        val snapshot = File(folder, "snapshot.sqlite")
        store.writeSnapshot(snapshot, includingVoicePrints = false)
        store.eraseEverything()
        assertNull(store.recording(recording.id))
        store.restoreSnapshot(snapshot)
        assertEquals("Kept", store.recording(recording.id)?.title)
        assertTrue(store.speakers(recording.id).single().embedding.isEmpty())
    }
}
