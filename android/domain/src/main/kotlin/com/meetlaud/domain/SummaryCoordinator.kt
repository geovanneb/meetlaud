package com.meetlaud.domain

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Instant
import java.util.UUID

/**
 * Runs summaries, one at a time, in steps that survive the app closing. A language model needs a lot of memory, so
 * this is the first thing to give way: it stops when the app leaves the foreground and when a recording starts, and
 * picks up from the last saved step (D-047).
 */
class SummaryCoordinator(
    private val store: SummaryStore,
    private val transcripts: TranscriptStore,
    private val speakers: SpeakerStore,
    private val engine: LanguageModelEngine,
    private val arbiter: ModelArbiter,
    private val models: (String) -> Pair<ModelDescriptor, File?>?,
    private val profile: () -> String? = { null },
    private val canRun: suspend () -> Boolean = { true },
) {
    object Limits {
        /** Tokens of transcript or notes per request. Leaves room for instructions and the answer. */
        const val CONTEXT_TOKENS = 1500
        /** Runs that end with the app gone. Stopping on purpose does not count. */
        const val ATTEMPTS = 3
    }

    private val lane = actorLane()
    private val scope = CoroutineScope(SupervisorJob() + lane)
    private val progressFlow = MutableStateFlow<Map<UUID, SummaryProgress>>(emptyMap())
    val updates: StateFlow<Map<UUID, SummaryProgress>> = progressFlow.asStateFlow()
    private var progress: Map<UUID, SummaryProgress>
        get() = progressFlow.value
        set(value) { progressFlow.value = value }

    private var worker: Job? = null
    private var running: UUID? = null
    /** The worker may hold a job it read just before this was cancelled, and saving it would bring it back. */
    private val cancelled = HashSet<UUID>()
    private var draft: Deferred<String>? = null
    /** A resume can arrive while the worker is stopping, and must not get lost. */
    private var resumeRequested = false

    val currentProgress: Map<UUID, SummaryProgress> get() = progress

    private suspend fun <T> isolated(block: suspend () -> T): T = withContext(lane) { block() }

    // MARK: - Queue

    suspend fun enqueue(id: RecordingID, template: SummaryTemplate, modelID: String, language: String?, now: Instant = Instant.now()): UUID = isolated {
        val summary = Summary(recordingID = id, templateName = template.name, modelID = modelID, language = language, createdAt = now)
        store.save(summary, SummaryJob(summary.id, id, template, modelID, language))
        progress = progress + (summary.id to SummaryProgress(SummaryProgress.Phase.QUEUED, 0.0))
        resumeInside()
        summary.id
    }

    /** Removes the job and whatever it wrote. The queue goes on with the next one. */
    suspend fun cancel(id: UUID) = isolated {
        cancelled.add(id)
        // A queued job is only rows. Stopping the worker could mean waiting for a long transcription.
        val isRunning = running == id
        if (isRunning) suspendInside()
        store.deleteSummaryJob(id)
        store.deleteSummary(id)
        progress = progress - id
        if (isRunning) resumeInside()
    }

    /** Stops generating right away. Everything already done stays saved. */
    suspend fun suspend() = isolated { suspendInside() }

    private suspend fun suspendInside() {
        draft?.cancel()
        val job = worker ?: return
        job.cancel()
        job.join()
    }

    /** Starts work if there is any and conditions allow it. Safe to call at any time. */
    fun resume() {
        scope.launch { resumeInside() }
    }

    private fun resumeInside() {
        if (worker != null) {
            resumeRequested = true
            return
        }
        worker = scope.launch { drainQueue() }
    }

    private suspend fun drainQueue() {
        try {
            // Asking for the model when there is nothing to do would make other work wait for no reason.
            val hasWork = runCatching { store.summaryJobs() }.getOrDefault(emptyList()).isNotEmpty()
            // Waiting must stay cancelable: `suspend` waits for this coroutine.
            if (hasWork && canRun() && runCatching { arbiter.acquireCancelable() }.isSuccess) {
                try {
                    processJobs()
                } finally {
                    withContext(NonCancellable) {
                        engine.unload()
                        arbiter.release()
                    }
                }
            }
        } catch (_: CancellationException) {
        } finally {
            // Cancellation stops database calls too, and this has to happen anyway.
            withContext(NonCancellable) { markWaiting() }
            worker = null
        }
        if (resumeRequested) {
            resumeRequested = false
            resumeInside()
        }
    }

    private suspend fun processJobs() {
        try {
            while (currentCoroutineContext().isActive) {
                val job = store.summaryJobs().firstOrNull() ?: break
                process(job)
            }
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (_: Exception) {
            // The store failed. The jobs stay saved, and the next resume goes on.
        }
    }

    private suspend fun process(original: SummaryJob) {
        if (original.summaryID in cancelled) return
        if (original.attempts >= Limits.ATTEMPTS) {
            abandon(original)
            return
        }
        running = original.summaryID
        try {
            val job = original.copy(attempts = original.attempts + 1)
            store.save(job)
            try {
                run(job)
            } catch (cancel: CancellationException) {
                withContext(NonCancellable) { refund(job.summaryID) }
                throw cancel
            } catch (error: Exception) {
                if (!currentCoroutineContext().isActive) {
                    withContext(NonCancellable) { refund(job.summaryID) }
                    throw CancellationException()
                }
                // A failed job would otherwise block the queue forever. What finished stays.
                abandon(job)
            }
        } finally {
            running = null
        }
    }

    private suspend fun refund(id: UUID) {
        val job = runCatching { store.summaryJobs() }.getOrNull()?.firstOrNull { it.summaryID == id } ?: return
        runCatching { store.save(job.copy(attempts = job.attempts - 1)) }
    }

    private suspend fun abandon(job: SummaryJob) {
        store.deleteSummaryJob(job.summaryID)
        progress = progress - job.summaryID
    }

    private suspend fun markWaiting() {
        for (job in runCatching { store.summaryJobs() }.getOrDefault(emptyList())) {
            progress = progress + (job.summaryID to SummaryProgress(SummaryProgress.Phase.WAITING, progress[job.summaryID]?.fraction ?: 0.0))
        }
    }

    // MARK: - Running

    private suspend fun run(original: SummaryJob) {
        var job = original
        val resolved = models(job.modelID) ?: throw TranscriptionException(TranscriptionError.MODEL_NOT_INSTALLED)
        val segments = transcripts.segments(job.recordingID)
        if (segments.isEmpty()) throw NothingToSummarizeException()
        progress = progress + (job.summaryID to SummaryProgress(SummaryProgress.Phase.READING, progress[job.summaryID]?.fraction ?: 0.0))
        engine.prepare(resolved.first, resolved.second)

        val people = speakers.speakers(job.recordingID)
        val lines = TranscriptFormatter.lines(segments, people)
        val spoken = transcripts.transcript(job.recordingID)?.language

        val duration = segments.lastOrNull()?.end ?: 0.0
        job = prepareNotes(job, lines, duration, spoken)
        var summary = store.summaries(job.recordingID).firstOrNull { it.id == job.summaryID }
            ?: Summary(job.summaryID, job.recordingID, job.template.name, job.modelID, job.language, createdAt = Instant.now())

        // A small model summarizes well in the language that was spoken, and translates well, but doing both at once
        // gave line-by-line translations and wrong numbers. So it writes in the spoken language, then translates.
        val languages = SummaryLanguages(spoken, job.language)
        val total = job.template.sections.size
        while (job.nextSection < total) {
            val section = job.template.sections[job.nextSection]
            val done = job.nextSection.toDouble() / total
            val written = sectionItems(section, job, duration, languages, done)
                .filter { belongs(it, section, segments, people) }
                // Checked before translating, so a date can still be found in the transcript.
                .map { SummaryValidator.validate(it, segments, people, sameLanguage = languages.written == spoken) }
            val items = inLanguage(written, section.kind, languages, keptNames(people, languages.target))
                .map { tokenized(it, people) }
            summary = summary.copy(sections = summary.sections + SummarySection(section.title, section.kind, items))
            job = job.copy(nextSection = job.nextSection + 1)
            store.save(summary, job)
            progress = progress + (job.summaryID to SummaryProgress(SummaryProgress.Phase.WRITING, job.nextSection.toDouble() / total))
        }

        store.complete(summary.copy(isComplete = true))
        progress = progress - job.summaryID
    }

    /** A long meeting is read part by part. Given all of it at once, a small model writes mostly about how it ended. */
    private suspend fun sectionItems(section: TemplateSection, job: SummaryJob, duration: TimeInterval, languages: SummaryLanguages, done: Double): List<SummaryItem> {
        val parts = if (job.nextChunk > 0) SummaryParts.split(job.notes, duration) else listOf(job.notes)
        val found = mutableListOf<List<SummaryItem>>()
        for (part in parts) {
            val request = SummaryPrompts.section(
                section, job.template, part, languages.written, languages.spoken, profile(),
                if (parts.size > 1) SummaryParts.limit(section.kind) else null,
            )
            val text = generate(request, job.summaryID to done)
            found.add(SummaryParser.items(text, section.kind))
        }
        return if (found.size > 1) SummaryParser.balanced(found, section.kind) else found.firstOrNull() ?: emptyList()
    }

    /** A short meeting goes straight to the model, since every summarizing step loses detail (D-046). */
    private suspend fun prepareNotes(original: SummaryJob, lines: List<String>, duration: TimeInterval, language: String?): SummaryJob {
        var job = original
        if (job.nextSection != 0) return job
        val chunks = TranscriptFormatter.chunks(lines, Limits.CONTEXT_TOKENS)
        if (chunks.size <= 1) return job.copy(notes = lines)
        while (job.nextChunk < chunks.size) {
            val text = generate(SummaryPrompts.notes(chunks[job.nextChunk], language))
            job = job.copy(notes = job.notes + SummaryParser.notes(text), nextChunk = job.nextChunk + 1)
            store.save(job)
            progress = progress + (job.summaryID to SummaryProgress(SummaryProgress.Phase.READING, job.nextChunk.toDouble() / chunks.size))
        }
        // Each stretch is condensed on its own: done all at once, this step lost the first two hours of a long meeting.
        val parts = SummaryParts.split(job.notes, duration).toMutableList()
        for (index in parts.indices) {
            parts[index] = condensed(parts[index], language)
            job = job.copy(notes = parts.flatten())
            store.save(job)
        }
        return job
    }

    private suspend fun condensed(original: List<String>, language: String?): List<String> {
        var notes = original
        var rounds = 0
        while (rounds < 3 && TokenEstimator.tokens(notes.joinToString("\n")) > Limits.CONTEXT_TOKENS) {
            val shorter = mutableListOf<String>()
            for (chunk in TranscriptFormatter.chunks(notes, Limits.CONTEXT_TOKENS)) {
                shorter += SummaryParser.notes(generate(SummaryPrompts.notes(chunk, language)))
            }
            notes = shorter
            rounds += 1
        }
        return notes
    }

    internal suspend fun generate(request: LanguageRequest, live: Pair<UUID, Double>? = null): String {
        // Conditions change between steps, such as the phone getting too hot.
        if (!canRun()) throw CancellationException()
        val text = StringBuilder()
        var chunks = 0
        engine.generate(request).collect { chunk ->
            currentCoroutineContext().ensureActive()
            text.append(chunk)
            chunks += 1
            // Often enough to read as typing, without redrawing on every token.
            if (live != null && chunks % 6 == 0) {
                progress = progress + (live.first to SummaryProgress(SummaryProgress.Phase.WRITING, live.second, text.toString()))
            }
        }
        // A cancelled stream ends quietly, and a partial answer must not pass for a finished one.
        currentCoroutineContext().ensureActive()
        return text.toString()
    }

    // MARK: - Translating

    /**
     * Brings every item into the language the person asked for: all of them when the summary was written in another
     * language, and otherwise only those the model let slip into one.
     */
    internal suspend fun inLanguage(items: List<SummaryItem>, kind: SectionKind, languages: SummaryLanguages, names: List<String>): List<SummaryItem> {
        val target = languages.target ?: return items
        val needed = items.indices.filter { languages.written != target || LanguageCheck.isWrong(items[it].text, target) }
        if (needed.isEmpty()) return items
        val result = items.toMutableList()
        var missing = mutableListOf<Int>()
        val batch = translations(needed.map { items[it] }, kind, target, names)
        if (batch.size == needed.size) {
            needed.zip(batch).forEach { (index, item) ->
                if (LanguageCheck.isWrong(item.text, target)) missing.add(index) else result[index] = translated(items[index], item, kind)
            }
        } else {
            // A model that merged or dropped a line would pair translations with the wrong citations.
            missing = needed.toMutableList()
        }
        for (index in missing) {
            val item = translations(listOf(items[index]), kind, target, names).firstOrNull()
            if (item != null && !LanguageCheck.isWrong(item.text, target)) result[index] = translated(items[index], item, kind)
            // One that still fails stays as it was: a point in the wrong language is better than a missing one.
        }
        return result
    }

    private suspend fun translations(items: List<SummaryItem>, kind: SectionKind, language: String, names: List<String>): List<SummaryItem> {
        val lines = items.map { SummaryParser.line(it, kind) }
        val text = generate(SummaryPrompts.translation(lines, language, names))
        return text.nonEmptyLines().mapNotNull { SummaryParser.items(it, kind).firstOrNull() }
    }

    // MARK: - Template drafts

    /** Turns a description into a template that a person can edit. */
    suspend fun draftTemplate(description: String, modelID: String, language: String?): SummaryTemplate {
        val resolved = models(modelID)
        if (!canRun() || resolved == null) throw TemplateException()
        isolated { suspendInside() }
        arbiter.acquire()
        val task = scope.async {
            engine.prepare(resolved.first, resolved.second)
            generate(SummaryPrompts.templateDraft(description, language))
        }
        isolated { draft = task }
        val result = runCatching { task.await() }
        isolated { draft = null }
        withContext(NonCancellable) {
            engine.unload()
            arbiter.release()
        }
        resume()
        return TemplateCodec.parseDraft(result.getOrThrow())
    }

    companion object {
        /** What the model wrote that cannot be a point of this section. */
        private fun belongs(item: SummaryItem, section: TemplateSection, segments: List<TranscriptSegment>, speakers: List<Speaker>): Boolean {
            if (section.kind == SectionKind.TASKS && SummaryValidator.isEchoedExample(item, segments)) return false
            // A statement in a section of questions is the decision or a task, listed again.
            if (SectionGuide.asksQuestions(section) && !SectionGuide.isQuestion(item.text)) return false
            // "Pedro?" alone says nothing.
            val letters = lettersAndNumbers(item.text)
            return speakers.mapNotNull { TranscriptFormatter.displayName(it) }.none { lettersAndNumbers(it) == letters }
        }

        private fun lettersAndNumbers(text: String) = buildString {
            text.codePoints().forEach { if (Character.isLetter(it) || isNumber(it)) appendCodePoint(it) }
        }

        private fun tokenized(item: SummaryItem, speakers: List<Speaker>): SummaryItem =
            item.copy(text = SpeakerTokens.encode(item.text, speakers), owner = item.owner?.let { SpeakerTokens.encode(it, speakers) })

        /** The words change. The citation, the owner, and whether it needs review stay those of the original. */
        private fun translated(original: SummaryItem, translation: SummaryItem, kind: SectionKind): SummaryItem {
            var item = original.copy(text = translation.text)
            if (kind == SectionKind.TASKS && original.due != null) item = item.copy(due = translation.due ?: original.due)
            return item
        }

        /**
         * Names the translation keeps as they are. Japanese text can hold a name in Latin letters, but a name in kanji
         * has to be romanized for English, Portuguese, or Spanish.
         */
        internal fun keptNames(speakers: List<Speaker>, language: String?): List<String> {
            val names = speakers.mapNotNull { TranscriptFormatter.displayName(it) }
            if (language == null || language == "ja") return names
            return names.filter { !LanguageCheck.isWrong(it, language) }
        }
    }
}

/** The languages of one summary. Any of them can be unknown. */
internal data class SummaryLanguages(
    /** What the transcript is in. */
    val spoken: String?,
    /** What the person picked, or null for the same as spoken. */
    val asked: String?,
) {
    /** What the model writes the sections in. */
    val written: String? get() = spoken ?: asked
    /** What the reader gets. */
    val target: String? get() = asked ?: spoken
}
