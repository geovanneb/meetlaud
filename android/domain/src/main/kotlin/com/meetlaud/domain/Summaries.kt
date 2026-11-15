package com.meetlaud.domain

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.descriptors.element
import kotlinx.serialization.encoding.CompositeDecoder
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.encoding.decodeStructure
import kotlinx.serialization.encoding.encodeStructure
import kotlinx.serialization.json.Json
import java.time.Instant
import java.util.UUID

/** The JSON that Swift's Codable writes and reads: nil keys left out, unknown keys ignored. */
val SwiftJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = true
}

/** RecordingID as Swift encodes it: an object holding its raw value. */
object RecordingIDSerializer : KSerializer<RecordingID> {
    override val descriptor = buildClassSerialDescriptor("RecordingID") { element<String>("rawValue") }

    override fun serialize(encoder: Encoder, value: RecordingID) =
        encoder.encodeStructure(descriptor) { encodeStringElement(descriptor, 0, value.rawValue.uuidString) }

    override fun deserialize(decoder: Decoder): RecordingID = decoder.decodeStructure(descriptor) {
        var raw = ""
        while (true) {
            when (val index = decodeElementIndex(descriptor)) {
                0 -> raw = decodeStringElement(descriptor, 0)
                CompositeDecoder.DECODE_DONE -> break
                else -> error("Unexpected index $index")
            }
        }
        RecordingID(UUID.fromString(raw))
    }
}

@Serializable
enum class SectionKind {
    @SerialName("bullets") BULLETS,
    @SerialName("tasks") TASKS;

    val raw: String get() = if (this == BULLETS) "bullets" else "tasks"
}

@Serializable
data class TemplateSection(val title: String, val kind: SectionKind = SectionKind.BULLETS)

@Serializable
enum class TemplateCategory {
    @SerialName("general") GENERAL,
    @SerialName("meeting") MEETING,
    @SerialName("speech") SPEECH,
    @SerialName("interview") INTERVIEW,
    @SerialName("call") CALL;

    val raw: String get() = name.lowercase()
}

/** How a summary is organized. Also the format of a template file, so that people can share them. */
@Serializable
data class SummaryTemplate(
    val id: String = UUID.randomUUID().uuidString,
    val name: String,
    val category: TemplateCategory,
    val instructions: String,
    val sections: List<TemplateSection>,
    val isBuiltIn: Boolean = false,
)

/** One statement in a summary. `sourceTime` is the proof: where the audio says it. */
@Serializable
data class SummaryItem(
    @Serializable(UUIDSerializer::class) val id: UUID = UUID.randomUUID(),
    val text: String,
    val sourceTime: TimeInterval? = null,
    /** Tasks only. Stored as written, or as a speaker token so that renaming reaches it. */
    val owner: String? = null,
    val due: String? = null,
    val isDone: Boolean = false,
    /** The model's claim could not be tied to the transcript, so a person should check it. */
    val needsReview: Boolean = false,
)

@Serializable
data class SummarySection(val title: String, val kind: SectionKind, val items: List<SummaryItem>)

data class Summary(
    val id: UUID = UUID.randomUUID(),
    val recordingID: RecordingID,
    val templateName: String,
    val modelID: String,
    val language: String?,
    val sections: List<SummarySection> = emptyList(),
    val isComplete: Boolean = false,
    val createdAt: Instant,
)

/** Work that survives the app closing, or the system taking the model away. */
@Serializable
data class SummaryJob(
    @Serializable(UUIDSerializer::class) val summaryID: UUID,
    @Serializable(RecordingIDSerializer::class) val recordingID: RecordingID,
    val template: SummaryTemplate,
    val modelID: String,
    val language: String?,
    val nextChunk: Int = 0,
    val notes: List<String> = emptyList(),
    val nextSection: Int = 0,
    /** Runs that never reached an end. A job that keeps killing the app has to stop being retried. */
    val attempts: Int = 0,
)

interface SummaryStore {
    suspend fun summaries(id: RecordingID): List<Summary>
    suspend fun save(summary: Summary)
    /** One transaction, so that a section can never be saved without its checkpoint, and written twice on resume. */
    suspend fun save(summary: Summary, job: SummaryJob)
    /** Marks it complete and removes its job, in one transaction. */
    suspend fun complete(summary: Summary)
    suspend fun deleteSummary(id: UUID)

    suspend fun summaryJobs(): List<SummaryJob>
    suspend fun save(job: SummaryJob)
    suspend fun deleteSummaryJob(summaryID: UUID)

    suspend fun userTemplates(): List<SummaryTemplate>
    suspend fun save(template: SummaryTemplate)
    suspend fun deleteTemplate(id: String)
}

/** Sends tasks to a task app, always from a person's explicit action. */
interface RemindersProvider {
    /** Throws `RemindersException` without access. */
    suspend fun add(title: String, notes: String?)

    /**
     * Called after the last task. Android has no shared task store as iOS has Reminders: its provider gathers the
     * tasks and hands them to the person's task app here, in one share.
     */
    suspend fun finish() = Unit
}

class NothingToSummarizeException : Exception("nothingToSummarize")

class RemindersException : Exception("denied")

data class SummaryProgress(
    val phase: Phase,
    val fraction: Double,
    /** What the model has written so far in the current section. */
    val partial: String? = null,
) {
    enum class Phase { QUEUED, READING, WRITING, WAITING }
}

/**
 * A summary as a tree: the meeting, its sections, and what each one says. Built from the summary itself, so that it
 * needs no model and every leaf keeps its link to the audio.
 */
data class MindMapNode(
    val id: String,
    val title: String,
    val time: TimeInterval? = null,
    val children: List<MindMapNode> = emptyList(),
) {
    companion object {
        /** Empty sections are left out: a branch with nothing on it says nothing. */
        fun tree(title: String, summary: Summary): MindMapNode {
            val branches = summary.sections.mapIndexedNotNull { index, section ->
                if (section.items.isEmpty()) return@mapIndexedNotNull null
                MindMapNode(
                    id = "section-$index",
                    title = section.title,
                    children = section.items.map { MindMapNode(it.id.uuidString, it.text, it.sourceTime) },
                )
            }
            return MindMapNode("root", title, children = branches)
        }
    }
}
