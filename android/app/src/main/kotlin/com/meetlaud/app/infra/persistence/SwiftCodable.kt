package com.meetlaud.app.infra.persistence

import com.meetlaud.domain.AskScope
import com.meetlaud.domain.Citation
import com.meetlaud.domain.FolderID
import com.meetlaud.domain.RecordingID
import com.meetlaud.domain.RecordingIDSerializer
import com.meetlaud.domain.SummaryJob
import com.meetlaud.domain.SummarySection
import com.meetlaud.domain.SummaryTemplate
import com.meetlaud.domain.SwiftJson
import com.meetlaud.domain.uuidString
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import java.util.UUID

/**
 * The JSON that the iOS app's `JSONEncoder` writes into the database, for the columns that hold JSON. Both apps must
 * read each other's files, so these shapes follow Swift's synthesized Codable exactly.
 */
internal object SwiftCodable {
    @Serializable
    private data class CitationRecord(
        val number: Int,
        @Serializable(RecordingIDSerializer::class) val recordingID: RecordingID,
        val recordingTitle: String,
        val time: Double,
        val excerpt: String,
    )

    @Serializable
    private data class StoredSegment(val start: Double, val end: Double, val text: String)

    private val citations = ListSerializer(CitationRecord.serializer())
    private val sections = ListSerializer(SummarySection.serializer())
    private val stored = ListSerializer(StoredSegment.serializer())

    fun encodeCitations(list: List<Citation>): ByteArray =
        SwiftJson.encodeToString(citations, list.map { CitationRecord(it.number, it.recordingID, it.recordingTitle, it.time, it.excerpt) }).encodeToByteArray()

    fun decodeCitations(data: ByteArray): List<Citation>? = runCatching {
        SwiftJson.decodeFromString(citations, data.decodeToString()).map { Citation(it.number, it.recordingID, it.recordingTitle, it.time, it.excerpt) }
    }.getOrNull()

    fun encodeSections(list: List<SummarySection>): ByteArray = SwiftJson.encodeToString(sections, list).encodeToByteArray()

    fun decodeSections(data: ByteArray): List<SummarySection>? = runCatching { SwiftJson.decodeFromString(sections, data.decodeToString()) }.getOrNull()

    fun encodeJob(job: SummaryJob): ByteArray = SwiftJson.encodeToString(SummaryJob.serializer(), job).encodeToByteArray()

    fun decodeJob(data: ByteArray): SummaryJob? = runCatching { SwiftJson.decodeFromString(SummaryJob.serializer(), data.decodeToString()) }.getOrNull()

    fun encodeTemplate(template: SummaryTemplate): ByteArray = SwiftJson.encodeToString(SummaryTemplate.serializer(), template).encodeToByteArray()

    fun decodeTemplate(data: ByteArray): SummaryTemplate? = runCatching { SwiftJson.decodeFromString(SummaryTemplate.serializer(), data.decodeToString()) }.getOrNull()

    fun encodeStoredSegments(list: List<Triple<Double, Double, String>>): ByteArray =
        SwiftJson.encodeToString(stored, list.map { StoredSegment(it.first, it.second, it.third) }).encodeToByteArray()

    fun decodeStoredSegments(data: ByteArray): List<Triple<Double, Double, String>>? = runCatching {
        SwiftJson.decodeFromString(stored, data.decodeToString()).map { Triple(it.start, it.end, it.text) }
    }.getOrNull()

    fun encodeAttendees(list: List<String>): String = SwiftJson.encodeToString(ListSerializer(String.serializer()), list)

    fun decodeAttendees(text: String): List<String> =
        runCatching { SwiftJson.decodeFromString(ListSerializer(String.serializer()), text) }.getOrDefault(emptyList())

    /**
     * Swift's synthesized Codable for an enum with values: `{"library":{}}`, `{"folder":{"_0":{"rawValue":"…"}}}`,
     * `{"recording":{"_0":{"rawValue":"…"}}}`.
     */
    fun encodeScope(scope: AskScope): ByteArray {
        val json = buildJsonObject {
            when (scope) {
                AskScope.Library -> putJsonObject("library") {}
                is AskScope.Folder -> putJsonObject("folder") { putJsonObject("_0") { put("rawValue", scope.id.rawValue.uuidString) } }
                is AskScope.Recording -> putJsonObject("recording") { putJsonObject("_0") { put("rawValue", scope.id.rawValue.uuidString) } }
            }
        }
        return json.toString().encodeToByteArray()
    }

    fun decodeScope(data: ByteArray): AskScope? = runCatching {
        val json = SwiftJson.parseToJsonElement(data.decodeToString()).jsonObject
        fun raw(case: JsonObject) = UUID.fromString(case["_0"]!!.jsonObject["rawValue"]!!.jsonPrimitive.content)
        when {
            "library" in json -> AskScope.Library
            "folder" in json -> AskScope.Folder(FolderID(raw(json["folder"]!!.jsonObject)))
            "recording" in json -> AskScope.Recording(RecordingID(raw(json["recording"]!!.jsonObject)))
            else -> null
        }
    }.getOrNull()
}
