package com.meetlaud.domain

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.takeWhile
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Instant
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * Answers one question at a time, from what is in the recordings and nothing else. A short meeting goes to the
 * model whole (D-046, D-052). Anything bigger goes through search: words and meaning together. The refusal comes
 * from the model and from checking its citations (D-051).
 */
class AskCoordinator(
    private val conversations: ConversationStore,
    knowledge: KnowledgeStore,
    recordings: RecordingStore,
    transcripts: TranscriptStore,
    speakers: SpeakerStore,
    summaries: SummaryStore? = null,
    private val language: LanguageModelEngine,
    private val embedder: TextEmbeddingEngine,
    indexer: KnowledgeIndexer,
    private val arbiter: ModelArbiter,
    private val models: (String) -> Pair<ModelDescriptor, File?>?,
    private val profile: () -> String? = { null },
    private val canRun: suspend () -> Boolean = { true },
    /** Summaries run for minutes, and a person waiting for an answer comes first. */
    private val pauseOtherWork: suspend () -> Unit = {},
    private val resumeOtherWork: suspend () -> Unit = {},
    private val keepWarm: Duration = Limits.KEEP_WARM,
) {
    object Limits {
        /** Tokens of excerpts per question. Leaves room for instructions, history, and the answer. */
        const val CONTEXT_TOKENS = 1500
        const val EXCERPTS = 8
        /** How long the model stays loaded after an answer. Follow-ups come quickly, and loading takes seconds (D-055). */
        val KEEP_WARM: Duration = 45.seconds
    }

    private val retriever = AskRetriever(knowledge, recordings, transcripts, speakers, summaries, language, embedder, indexer)
    private val lane = actorLane()
    private val scope = CoroutineScope(SupervisorJob() + lane)
    private var current: Job? = null
    /** The turn is still ours and the model is still loaded, ready for the next question. */
    private var isWarm = false
    private var warmTimer: Job? = null

    private suspend fun <T> isolated(block: suspend () -> T): T = withContext(lane) { block() }

    /** Saves the question first, so that nothing the person typed gets lost. A new question stops the previous answer. */
    suspend fun ask(question: String, conversation: Conversation, modelID: String?, skill: String? = null, now: Instant = Instant.now()): Flow<AskUpdate> = isolated {
        stopInside()
        val channel = Channel<Any>(Channel.UNLIMITED)
        current = scope.launch {
            val reply = reply(question, conversation, modelID, skill, now) { channel.trySend(it) }
            channel.trySend(AskUpdate.Finished(reply))
            channel.close()
        }
        @Suppress("UNCHECKED_CAST")
        channel.receiveAsFlow() as Flow<AskUpdate>
    }

    /** Ends the answer. What was already written stays, marked as stopped. */
    suspend fun stop() = isolated { stopInside() }

    private suspend fun stopInside() {
        val job = current ?: return
        job.cancel()
        job.join()
        current = null
    }

    /** Ends the answer and frees the model now. For leaving the foreground, and for a recording about to start. */
    suspend fun stopAndRelease() = isolated {
        stopInside()
        releaseWarmModel()
    }

    val holdsWarmModel: Boolean get() = isWarm

    private suspend fun releaseWarmModel() {
        warmTimer?.cancel()
        warmTimer = null
        if (!isWarm) return
        isWarm = false
        release(true)
    }

    private fun stayWarm() {
        isWarm = true
        warmTimer?.cancel()
        warmTimer = scope.launch {
            delay(keepWarm)
            releaseWarmModel()
        }
    }

    private suspend fun reply(question: String, original: Conversation, modelID: String?, skill: String?, now: Instant, update: (AskUpdate) -> Unit): ChatMessage {
        var conversation = original.copy(updatedAt = now)
        if (conversation.title.isEmpty()) conversation = conversation.copy(title = question.prefixCharacters(60))
        val history = runCatching { conversations.messages(conversation.id) }.getOrDefault(emptyList())
        val asked = ChatMessage(conversationID = conversation.id, role = ChatRole.USER, body = question, createdAt = now)
        persist(conversation, asked)

        var message = ChatMessage(conversationID = conversation.id, role = ChatRole.ASSISTANT, body = "", state = AnswerState.FAILED, createdAt = now)
        val fact = MemoryCommand.text(question)
        val resolved = modelID?.let(models)
        if (fact != null) {
            runCatching { conversations.save(MemoryItem(text = fact, createdAt = now)) }
            message = message.copy(body = fact, state = AnswerState.REMEMBERED)
        } else if (resolved != null) {
            message = answer(Turn(question, conversation, history, resolved, skill), message, update)
        }
        persist(null, message)
        return message
    }

    /** Cancellation stops database calls too, and these saves have to happen anyway. */
    private suspend fun persist(conversation: Conversation?, message: ChatMessage) = withContext(NonCancellable) {
        conversation?.let { runCatching { conversations.save(it) } }
        runCatching { conversations.save(message) }
    }

    private class Turn(
        val question: String,
        val conversation: Conversation,
        val history: List<ChatMessage>,
        val model: Pair<ModelDescriptor, File?>,
        val skill: String?,
    )

    private suspend fun answer(turn: Turn, original: ChatMessage, update: (AskUpdate) -> Unit): ChatMessage {
        var message = original
        var written = ""
        var excerpts = emptyList<AskExcerpt>()
        // A warm model keeps the turn from the last answer, and other work is already paused.
        var holdsModel = isWarm
        try {
            takeTurn(update)
            holdsModel = true
            update(AskUpdate.Searching)
            excerpts = retriever.excerpts(turn.question, turn.conversation.scope, turn.history)
            if (excerpts.isEmpty()) {
                release(holdsModel)
                return message.copy(state = AnswerState.NO_BASIS)
            }
            language.prepare(turn.model.first, turn.model.second)
            val request = AskPrompts.answer(turn.question, excerpts, turn.history, conversations.memories(), profile(), turn.skill)
            if (!canRun()) throw CancellationException()
            var stopped = false
            language.generate(request).takeWhile { !stopped }.collect { chunk ->
                currentCoroutineContext().ensureActive()
                written += chunk
                // A small model that has said what it knows often goes on to recite its sources. That is never part
                // of the answer, so it ends the answer.
                val copying = AnswerParser.copyingStart(written)
                if (copying != null) {
                    written = written.substring(0, copying)
                    stopped = true
                } else {
                    update(AskUpdate.Writing(AnswerParser.visible(written)))
                }
            }
            currentCoroutineContext().ensureActive()
            val result = AnswerParser.parse(written, excerpts)
            // A citation at the start of its passage still works, so this can never cost the answer.
            val located = runCatching { retriever.located(result.citations, result.body, excerpts) }.getOrNull()
            message = message.copy(
                body = result.body,
                citations = located ?: result.citations,
                state = if (result.hasBasis) AnswerState.COMPLETE else AnswerState.NO_BASIS,
            )
            stayWarm()
            return message
        } catch (error: Exception) {
            // Engines report cancellation in their own way, so the coroutine is what counts.
            if (error is CancellationException || !currentCoroutineContext().isActive) {
                val result = AnswerParser.parse(written, excerpts)
                message = message.copy(
                    body = if (result.hasBasis) result.body else AnswerParser.visible(written),
                    citations = result.citations,
                    state = AnswerState.STOPPED,
                )
            }
        }
        release(holdsModel)
        return message
    }

    /** Gets the right to use the model, unless the last answer left it warm. */
    private suspend fun takeTurn(update: (AskUpdate) -> Unit) {
        val wasWarm = isWarm
        warmTimer?.cancel()
        isWarm = false
        if (!wasWarm) pauseOtherWork()
        if (!canRun()) throw CancellationException()
        if (!wasWarm && !arbiter.tryAcquire()) {
            update(AskUpdate.Waiting)
            arbiter.acquireCancelable()
        }
    }

    private suspend fun release(holdsModel: Boolean) = withContext(NonCancellable) {
        if (holdsModel) {
            language.unload()
            embedder.unload()
            arbiter.release()
        }
        resumeOtherWork()
    }
}

/** Finds what a question should read, and where in the audio an answer's claims really are. */
internal class AskRetriever(
    private val knowledge: KnowledgeStore,
    private val recordings: RecordingStore,
    private val transcripts: TranscriptStore,
    private val speakers: SpeakerStore,
    private val summaries: SummaryStore?,
    private val language: LanguageModelEngine,
    private val embedder: TextEmbeddingEngine,
    private val indexer: KnowledgeIndexer,
) {
    private object Limits {
        /** How many each search brings in before merging. */
        const val CANDIDATES = 24
        /** The summary's share of the context. Search results get the rest. */
        const val SUMMARY_TOKENS = 600
    }

    suspend fun excerpts(question: String, scope: AskScope, history: List<ChatMessage>): List<AskExcerpt> {
        val id = scope.recordingID ?: return search(question, scope, history)
        val recording = recordings.recording(id)
        if (recording == null || recording.deletedAt != null) return emptyList()
        val segments = transcripts.segments(id)
        if (segments.isEmpty()) return emptyList()
        val people = speakers.speakers(id)
        // "What was it about?" shares no words with any passage. The summary already answers it, and each of its
        // points is tied to a moment, so a citation still lands on the transcript.
        val overview = summaryExcerpts(id, segments, recording.title)
        wholeMeeting(segments, people, recording.title, overview)?.let { return overview + it }
        // A person can ask about a long meeting the moment it finishes, before the background work gets to it.
        indexIfStale(id)
        return withinBudget(overview + search(question, scope, history))
    }

    /** The points of the newest summary that are tied to a phrase. A point flagged for review is left out (D-049). */
    private suspend fun summaryExcerpts(id: RecordingID, segments: List<TranscriptSegment>, title: String): List<AskExcerpt> {
        val summary = summaries?.summaries(id)?.maxByOrNull { it.createdAt } ?: return emptyList()
        val result = mutableListOf<AskExcerpt>()
        var tokens = 0
        for (section in summary.sections) {
            for (item in section.items) {
                if (item.needsReview) continue
                val time = item.sourceTime ?: continue
                val segment = segments.lastOrNull { it.start <= time } ?: segments.firstOrNull() ?: continue
                val text = "Summary, ${section.title}: ${item.text}"
                tokens += TokenEstimator.tokens(text) + 2
                if (tokens > Limits.SUMMARY_TOKENS) return result
                // The passage is that one phrase, so the citation shows what was said, not the summary's words.
                result.add(AskExcerpt(id, title, segment.start, segment.end, text))
            }
        }
        return result
    }

    private suspend fun indexIfStale(id: RecordingID) {
        val state = knowledge.indexStates()[id]
        val segments = transcripts.segments(id)
        val people = speakers.speakers(id)
        if (state?.sourceHash != KnowledgeChunker.sourceHash(segments, people)) {
            language.unload()
            indexer.index(id)
        }
    }

    private suspend fun search(question: String, scope: AskScope, history: List<ChatMessage>): List<AskExcerpt> {
        // "And who will do it?" only makes sense next to the question before it.
        val previous = history.lastOrNull { it.role == ChatRole.USER }?.body ?: ""
        val terms = QueryTerms.terms("$question $previous")
        val lists = mutableListOf(knowledge.lexicalMatches(terms, scope, Limits.CANDIDATES))

        val spoken = embedder.detectLanguage(question)
        val modelID = embedder.modelID(spoken)
        if (modelID != null) {
            // One model at a time, and a warm language model may still be loaded.
            language.unload()
            val vectors = embedder.embed(listOf("$previous $question"), spoken)
            embedder.unload()
            vectors.firstOrNull()?.let { lists.add(knowledge.nearest(it, modelID, scope, Limits.CANDIDATES)) }
        }
        val ids = RankFusion.merge(lists, AskCoordinator.Limits.EXCERPTS)
        val found = knowledge.chunks(ids)
        val titles = HashMap<RecordingID, String?>()
        return ids.mapNotNull { id ->
            val chunk = found.firstOrNull { it.id == id } ?: return@mapNotNull null
            if (chunk.recordingID !in titles) titles[chunk.recordingID] = recordings.recording(chunk.recordingID)?.title
            AskExcerpt(chunk.recordingID, titles[chunk.recordingID] ?: "", chunk.start, chunk.end, chunk.text)
        }
    }

    /** A passage lasts about a minute, and the link should land on the phrase that matters (D-057). */
    suspend fun located(citations: List<Citation>, body: String, excerpts: List<AskExcerpt>): List<Citation> = citations.map { citation ->
        val end = excerpts.firstOrNull { it.recordingID == citation.recordingID && it.time == citation.time && it.text == citation.excerpt }?.end
            ?: return@map citation
        val passage = transcripts.segments(citation.recordingID).filter { it.start >= citation.time && it.start < end }
        val people = speakers.speakers(citation.recordingID)
        val claim = CitationLocator.claim(citation.number, body)
        val segment = CitationLocator.phrase(claim, passage) ?: return@map citation
        citation.copy(time = segment.start, excerpt = KnowledgeChunker.speakerLine(segment, people))
    }

    companion object {
        /** Keeps the excerpts in order until the context is full. */
        private fun withinBudget(excerpts: List<AskExcerpt>): List<AskExcerpt> {
            var tokens = 0
            val result = mutableListOf<AskExcerpt>()
            for (excerpt in excerpts) {
                tokens += TokenEstimator.tokens(excerpt.text) + 2
                if (tokens > AskCoordinator.Limits.CONTEXT_TOKENS) break
                result.add(excerpt)
            }
            return result
        }

        /** The whole meeting as a few passages, when it fits next to the summary. */
        private fun wholeMeeting(segments: List<TranscriptSegment>, speakers: List<Speaker>, title: String, overview: List<AskExcerpt>): List<AskExcerpt>? {
            val excerpts = KnowledgeChunker.chunks(segments, speakers, null).map { AskExcerpt(it.recordingID, title, it.start, it.end, it.text) }
            val tokens = (overview + excerpts).sumOf { TokenEstimator.tokens(it.text) + 2 }
            return if (tokens <= AskCoordinator.Limits.CONTEXT_TOKENS) excerpts else null
        }
    }
}
