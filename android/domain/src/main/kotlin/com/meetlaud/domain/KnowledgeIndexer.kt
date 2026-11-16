package com.meetlaud.domain

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.time.Duration.Companion.seconds

/**
 * Keeps the search index in step with the transcripts, a little at a time. It compares what each transcript looks
 * like now against what was indexed, so there is nothing to invalidate by hand.
 */
class KnowledgeIndexer(
    private val recordings: RecordingStore,
    private val transcripts: TranscriptStore,
    private val speakers: SpeakerStore,
    private val knowledge: KnowledgeStore,
    private val engine: TextEmbeddingEngine,
    private val arbiter: ModelArbiter,
    private val canRun: suspend () -> Boolean = { true },
) {
    private val lane = actorLane()
    private val scope = CoroutineScope(SupervisorJob() + lane)
    private var worker: Job? = null
    private var runRequested = false
    private val progress = MutableStateFlow<IndexProgress?>(null)
    val updates: StateFlow<IndexProgress?> = progress.asStateFlow()

    /** Starts indexing if anything changed. Safe to call at any time. */
    fun run() {
        scope.launch {
            if (worker != null) {
                runRequested = true
                return@launch
            }
            worker = scope.launch { work() }
        }
    }

    /** Stops after the current batch of text. The next run goes on from there. */
    suspend fun suspend() {
        val job = withContext(lane) { worker } ?: return
        job.cancel()
        job.join()
    }

    val isRunning: Boolean get() = worker != null

    private suspend fun work() {
        try {
            val pending = staleRecordings()
            for ((done, id) in pending.withIndex()) {
                progress.value = IndexProgress(done, pending.size)
                if (!canRun()) break
                // One recording per turn, so that a person asking something never waits for the whole library.
                arbiter.acquireCancelable(1.seconds)
                try {
                    index(id)
                } catch (error: Exception) {
                    if (!currentCoroutineContext().isActive) {
                        handBack()
                        throw error
                    }
                    // A recording that was deleted a moment ago must not stop the others.
                }
                handBack()
            }
        } catch (_: Exception) {
            // Stopped, or the store failed. Nothing is half written, and the next run finds what is left.
        }
        progress.value = null
        worker = null
        if (runRequested) {
            runRequested = false
            run()
        }
    }

    private suspend fun handBack() = withContext(NonCancellable) {
        engine.unload()
        arbiter.release()
    }

    private suspend fun staleRecordings(): List<RecordingID> {
        val states = knowledge.indexStates()
        return recordings.recordings(RecordingStatus.READY)
            .filter { it.deletedAt == null }
            .filter { needsIndexing(it.id, states[it.id]) }
            .map { it.id }
    }

    private suspend fun needsIndexing(id: RecordingID, indexed: KnowledgeIndexState?): Boolean {
        val transcript = transcripts.transcript(id)
        // The transcript was removed, and its text must not stay findable.
        if (transcript == null || !transcript.isComplete) return indexed != null
        val segments = transcripts.segments(id)
        val people = speakers.speakers(id)
        if (indexed == null) return segments.isNotEmpty()
        val language = language(id, segments)
        return indexed != KnowledgeIndexState(KnowledgeChunker.sourceHash(segments, people), engine.modelID(language))
    }

    private suspend fun language(id: RecordingID, segments: List<TranscriptSegment>): String? {
        transcripts.transcript(id)?.language?.let { return it }
        return engine.detectLanguage(segments.take(20).joinToString(" ") { it.text })
    }

    /** Rebuilds one recording. The caller holds the arbiter. */
    internal suspend fun index(id: RecordingID) {
        val transcript = transcripts.transcript(id)
        if (transcript == null || !transcript.isComplete) {
            knowledge.removeChunks(id)
            return
        }
        val segments = transcripts.segments(id)
        val people = speakers.speakers(id)
        val language = language(id, segments)
        var chunks = KnowledgeChunker.chunks(segments, people, language)
        val modelID = engine.modelID(language)
        if (modelID != null) chunks = embedded(chunks, language, modelID)
        // Without a model the chunks still go in, because search by words works with no model at all.
        knowledge.replaceChunks(chunks, id, KnowledgeIndexState(KnowledgeChunker.sourceHash(segments, people), modelID))
    }

    private suspend fun embedded(chunks: List<KnowledgeChunk>, language: String?, modelID: String): List<KnowledgeChunk> {
        val result = ArrayList<KnowledgeChunk>(chunks.size)
        // Batches are the points where it can stop, or let the phone breathe.
        for (batch in chunks.chunked(16)) {
            currentCoroutineContext().ensureActive()
            val vectors = engine.embed(batch.map { it.text }, language)
            batch.zip(vectors).forEach { (chunk, vector) ->
                result.add(chunk.copy(language = language, modelID = modelID, vector = vector))
            }
        }
        return result
    }
}
