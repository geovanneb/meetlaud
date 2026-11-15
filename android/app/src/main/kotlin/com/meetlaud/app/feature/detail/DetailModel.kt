package com.meetlaud.app.feature.detail

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.meetlaud.app.feature.shared.SummaryCenter
import com.meetlaud.app.feature.shared.TranscribeOutcome
import com.meetlaud.app.feature.shared.TranscriptionCenter
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.localization.sectionTitle
import com.meetlaud.domain.AudioPlaying
import com.meetlaud.domain.ExportOptions
import com.meetlaud.domain.JobProgress
import com.meetlaud.domain.LibraryService
import com.meetlaud.domain.Marker
import com.meetlaud.domain.PauseSpan
import com.meetlaud.domain.Person
import com.meetlaud.domain.Recording
import com.meetlaud.domain.RecordingFiles
import com.meetlaud.domain.RecordingID
import com.meetlaud.domain.RecordingStore
import com.meetlaud.domain.RemindersProvider
import com.meetlaud.domain.SectionKind
import com.meetlaud.domain.Speaker
import com.meetlaud.domain.SpeakerCount
import com.meetlaud.domain.SpeakerException
import com.meetlaud.domain.SpeakerService
import com.meetlaud.domain.SpeakerStore
import com.meetlaud.domain.SpeakerTokens
import com.meetlaud.domain.Summary
import com.meetlaud.domain.SummaryExporter
import com.meetlaud.domain.SummaryItem
import com.meetlaud.domain.SummaryProgress
import com.meetlaud.domain.SummaryTemplate
import com.meetlaud.domain.TimeInterval
import com.meetlaud.domain.TranscribePlan
import com.meetlaud.domain.Transcript
import com.meetlaud.domain.TranscriptExporter
import com.meetlaud.domain.TranscriptFormat
import com.meetlaud.domain.TranscriptSegment
import com.meetlaud.domain.TranscriptStore
import com.meetlaud.domain.TranscriptVersion
import com.meetlaud.domain.uuidString
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import java.io.File
import java.util.UUID
import kotlin.coroutines.coroutineContext

/** One meeting's screen state, as DetailModel.swift. */
class DetailModel(
    val id: RecordingID,
    val startTime: TimeInterval?,
    private val store: RecordingStore,
    val files: RecordingFiles,
    private val player: AudioPlaying,
    private val library: LibraryService,
    private val transcripts: TranscriptStore,
    val center: TranscriptionCenter,
    private val speakerStore: SpeakerStore,
    private val speakerService: SpeakerService,
    val summaryCenter: SummaryCenter,
    val reminders: RemindersProvider,
) {
    var recording by mutableStateOf<Recording?>(null)
        private set
    var markers by mutableStateOf<List<Marker>>(emptyList())
        private set
    var pauses by mutableStateOf<List<PauseSpan>>(emptyList())
        private set
    var time by mutableStateOf(0.0)
        private set
    var isPlaying by mutableStateOf(false)
        private set
    var failed by mutableStateOf(false)
        private set
    var rate by mutableStateOf(1f)
        private set

    var segments by mutableStateOf<List<TranscriptSegment>>(emptyList())
        private set
    var transcript by mutableStateOf<Transcript?>(null)
        private set
    var activeSegmentID by mutableStateOf<UUID?>(null)
        private set
    var speakers by mutableStateOf<List<Speaker>>(emptyList())
        private set
    var hasAudio by mutableStateOf(true)
        private set
    var summaries by mutableStateOf<List<Summary>>(emptyList())
        internal set
    var selectedSummaryID by mutableStateOf<UUID?>(null)
    private var activeSegmentIndex: Int? = null

    val duration: Double get() = maxOf(player.duration, recording?.duration ?: 0.0)

    suspend fun load() {
        try {
            recording = store.recording(id)
            markers = store.markers(id)
            pauses = store.pauses(id)
            val recording = recording ?: run {
                failed = true
                return
            }
            refreshTranscript()
            refreshSummaries()
            try {
                player.load(files.audioFile(id), recording.title)
                startTime?.let { seek(it) }
            } catch (_: Exception) {
                // Text is still worth reading with no audio, so only an empty recording counts as a failure.
                hasAudio = false
                failed = segments.isEmpty()
            }
        } catch (_: Exception) {
            failed = true
        }
    }

    /** Follows the player while the screen is open. The caller's scope ends it when the screen goes away. */
    suspend fun trackPlayback() {
        while (coroutineContext.isActive) {
            time = player.currentTime
            isPlaying = player.isPlaying
            updateActiveSegment()
            delay(100)
        }
    }

    suspend fun refreshTranscript() {
        transcript = runCatching { transcripts.transcript(id) }.getOrNull()
        segments = runCatching { transcripts.segments(id) }.getOrDefault(emptyList())
        activeSegmentIndex = null
        updateActiveSegment()
        speakers = runCatching { speakerStore.speakers(id) }.getOrDefault(emptyList())
    }

    fun speaker(segment: TranscriptSegment): Speaker? = speakers.firstOrNull { it.id.uuidString == segment.speaker }

    fun name(speaker: Speaker): String = speaker.name ?: L10n.People.numbered(speaker.number)

    suspend fun savedPeople(): List<Person> = runCatching { speakerStore.people() }.getOrDefault(emptyList())

    suspend fun rename(speaker: Speaker, name: String) {
        runCatching { speakerService.rename(speaker, name) }
        refreshTranscript()
    }

    suspend fun assign(speaker: Speaker, person: Person) {
        runCatching { speakerService.assign(speaker, person) }
        refreshTranscript()
    }

    suspend fun merge(speaker: Speaker, target: Speaker) {
        runCatching { speakerService.merge(speaker, target) }
        refreshTranscript()
    }

    suspend fun confirm(speaker: Speaker) {
        runCatching { speakerService.confirm(speaker) }
        refreshTranscript()
    }

    suspend fun setSpeaker(speaker: Speaker, segment: TranscriptSegment) {
        runCatching { speakerService.setSpeaker(speaker, segment.id) }
        refreshTranscript()
    }

    enum class SaveVoiceResult { SAVED, TOO_LITTLE_SPEECH, UNAVAILABLE }

    suspend fun saveVoice(speaker: Speaker, name: String): SaveVoiceResult = try {
        speakerService.saveVoicePrint(speaker, name)
        refreshTranscript()
        SaveVoiceResult.SAVED
    } catch (error: SpeakerException) {
        if (error.reason == SpeakerException.Reason.TOO_LITTLE_SPEECH) SaveVoiceResult.TOO_LITTLE_SPEECH else SaveVoiceResult.UNAVAILABLE
    } catch (_: Exception) {
        SaveVoiceResult.UNAVAILABLE
    }

    // MARK: - Playback

    private fun updateActiveSegment() {
        // Near the same place almost always, and a transcript can hold thousands of phrases.
        activeSegmentIndex?.let { index ->
            val current = segments.getOrNull(index)
            if (current != null && current.start <= time && time < current.end) return
        }
        activeSegmentIndex = segments.indexOfLast { it.start <= time && time < it.end + 0.5 }.takeIf { it >= 0 }
        activeSegmentID = activeSegmentIndex?.let { segments[it].id }
    }

    val progress: JobProgress? get() = center.progress[id]

    /** Voices separated again on a finished transcript. The text is there, so only the speakers show work. */
    val isRedetectingSpeakers: Boolean get() = progress?.phase == JobProgress.Phase.SEPARATING_SPEAKERS && transcript?.isComplete == true

    /** A transcription at work, with its steps. Null while only voices are separated again. */
    val transcriptionProgress: JobProgress? get() = if (isRedetectingSpeakers) null else progress

    suspend fun transcribe(language: String?, whenCharging: Boolean = false): TranscribeOutcome = center.transcribe(id, language, whenCharging)

    suspend fun transcribePlan(language: String?): TranscribePlan? = center.plan(recording?.duration ?: 0.0, language)

    suspend fun versions(): List<TranscriptVersion> = runCatching { transcripts.versions(id) }.getOrDefault(emptyList())

    suspend fun restore(version: TranscriptVersion) {
        center.restore(version)
        refreshTranscript()
    }

    suspend fun canSeparateSpeakers(): Boolean = center.canSeparateSpeakers()

    suspend fun redetectSpeakers(count: SpeakerCount) {
        center.redetectSpeakers(id, count)
        refreshTranscript()
    }

    suspend fun cancelTranscription() {
        center.cancel(id)
        refreshTranscript()
    }

    suspend fun save(segment: TranscriptSegment) {
        runCatching { transcripts.update(segment) }
        refreshTranscript()
    }

    suspend fun replaceAll(text: String, replacement: String): Int {
        val count = runCatching { transcripts.replaceAll(id, text, replacement) }.getOrDefault(0)
        refreshTranscript()
        return count
    }

    fun togglePlayback() {
        if (player.isPlaying) player.pause() else player.play()
        isPlaying = player.isPlaying
    }

    fun seek(target: Double) {
        player.seek(target)
        time = player.currentTime
        updateActiveSegment()
    }

    fun play(target: Double) {
        seek(target)
        if (!player.isPlaying) togglePlayback()
    }

    fun changeRate(value: Float) {
        rate = value
        player.rate = value
    }

    fun close() = player.stop()

    suspend fun rename(title: String) {
        runCatching { library.rename(id, title) }
        recording = runCatching { store.recording(id) }.getOrNull()
    }

    suspend fun moveToTrash() {
        runCatching { library.trash(listOf(id)) }
    }

    fun image(marker: Marker): Bitmap? {
        val name = marker.attachment ?: return null
        return runCatching { BitmapFactory.decodeFile(File(files.attachmentsDirectory(id), name).path) }.getOrNull()
    }

    // MARK: - Summaries, as DetailModel+Summaries.swift

    /** Coming from a search result or a link means someone wants a specific moment, so that stays on the transcript. */
    val opensOnSummary: Boolean get() = startTime == null && summaries.isNotEmpty()

    val audioFile: File get() = files.audioFile(id)

    fun exportedTranscript(format: TranscriptFormat, options: ExportOptions): String =
        TranscriptExporter.text(recording?.title ?: "", segments, speakers, format, options)

    fun exportedSummary(): String {
        val summary = selectedSummary ?: return ""
        return SummaryExporter.markdown(recording?.title ?: "", summary, speakers)
    }

    val selectedSummary: Summary? get() = summaries.firstOrNull { it.id == selectedSummaryID } ?: summaries.lastOrNull()

    val templates: List<SummaryTemplate> get() = summaryCenter.templates

    val defaultTemplate: SummaryTemplate get() = summaryCenter.defaultTemplate

    fun template(summary: Summary): SummaryTemplate? = templates.firstOrNull { it.name == summary.templateName }

    /** Changes when a step ends, and stays the same while text streams in. */
    val summarySteps: Map<UUID, Double> get() = summaryCenter.progress.mapValues { it.value.fraction }

    fun progress(summary: Summary): SummaryProgress? = summaryCenter.progress[summary.id]

    suspend fun refreshSummaries() {
        summaries = summaryCenter.summaries(id)
        if (selectedSummaryID == null || summaries.none { it.id == selectedSummaryID }) selectedSummaryID = summaries.lastOrNull()?.id
        summaryCenter.reloadTemplates()
    }

    suspend fun summarize(template: SummaryTemplate, language: String?): TranscribeOutcome {
        val outcome = summaryCenter.summarize(id, template, language)
        refreshSummaries()
        selectedSummaryID = summaries.lastOrNull()?.id
        return outcome
    }

    suspend fun cancel(summary: Summary) {
        summaryCenter.cancel(summary.id)
        refreshSummaries()
    }

    suspend fun deleteSelectedSummary() {
        val summary = selectedSummary ?: return
        if (summaryCenter.progress[summary.id] != null) summaryCenter.cancel(summary.id) else summaryCenter.delete(summary)
        selectedSummaryID = null
        refreshSummaries()
    }

    suspend fun toggle(item: SummaryItem, summary: Summary) {
        val updated = summary.copy(sections = summary.sections.map { section ->
            section.copy(items = section.items.map { if (it.id == item.id) it.copy(isDone = !it.isDone) else it })
        })
        summaryCenter.save(updated)
        refreshSummaries()
    }

    /** Text with speakers as they are named right now, so that renaming needs no new summary. */
    fun display(text: String): String = SpeakerTokens.decode(text, speakers) { name(it) }

    fun detail(item: SummaryItem): String? {
        val parts = listOfNotNull(item.owner?.let(::display), item.due)
        return if (parts.isEmpty()) null else parts.joinToString(" · ")
    }

    val openTasks: List<SummaryItem>
        get() = (selectedSummary?.sections ?: emptyList()).filter { it.kind == SectionKind.TASKS }.flatMap { it.items }.filter { !it.isDone }

    /** False when the task app could not be reached. */
    suspend fun sendTasksToReminders(): Boolean {
        val source = recording?.title
        for (task in openTasks) {
            val notes = listOfNotNull(detail(task), source).joinToString("\n")
            try {
                reminders.add(display(task.text), notes)
            } catch (_: Exception) {
                return false
            }
        }
        return runCatching { reminders.finish() }.isSuccess
    }

    fun plainText(summary: Summary): String {
        val lines = mutableListOf(recording?.title ?: "")
        for (section in summary.sections) {
            lines.add("\n${L10n.Summary.sectionTitle(section.title)}")
            for (item in section.items) {
                val detail = detail(item)?.let { " ($it)" } ?: ""
                lines.add("- ${display(item.text)}$detail")
            }
        }
        return lines.joinToString("\n")
    }
}
