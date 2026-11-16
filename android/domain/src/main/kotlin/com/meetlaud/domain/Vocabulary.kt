package com.meetlaud.domain

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.util.UUID

/** Writes a UUID the way Swift's Codable does: uppercase text. */
object UUIDSerializer : KSerializer<UUID> {
    override val descriptor = PrimitiveSerialDescriptor("UUID", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: UUID) = encoder.encodeString(value.toString().uppercase())
    override fun deserialize(decoder: Decoder): UUID = UUID.fromString(decoder.decodeString())
}

/** A folder id in JSON, as Swift encodes FolderID: an object holding its raw value. */
@Serializable
private data class FolderIDBox(@Serializable(UUIDSerializer::class) val rawValue: UUID)

/** A word the engine gets wrong, and how it should be written. Names of people, products, and companies, mostly. */
data class VocabularyEntry(
    val id: UUID = UUID.randomUUID(),
    val heard: String,
    val written: String,
    /** Null applies to every recording. A folder applies only to the recordings in it. */
    val folderID: FolderID? = null,
) {
    val isValid: Boolean get() = heard.trimmedWhitespace().isNotEmpty() && written.trimmedWhitespace().isNotEmpty()

    internal val key: String get() = FoldedText.fold(heard.trimmedWhitespace())
}

@Serializable
private data class VocabularyRecord(
    @Serializable(UUIDSerializer::class) val id: UUID,
    val heard: String,
    val written: String,
    val folderID: FolderIDBox? = null,
)

object VocabularyPreferences {
    const val KEY = "transcript.vocabulary"
    private val json = Json { ignoreUnknownKeys = true }
    private val serializer = ListSerializer(VocabularyRecord.serializer())

    fun load(defaults: Preferences): List<VocabularyEntry> {
        val text = defaults.string(KEY) ?: return emptyList()
        return runCatching { json.decodeFromString(serializer, text) }.getOrDefault(emptyList()).map {
            VocabularyEntry(it.id, it.heard, it.written, it.folderID?.let { box -> FolderID(box.rawValue) })
        }
    }

    fun save(entries: List<VocabularyEntry>, defaults: Preferences) {
        val records = entries.map { VocabularyRecord(it.id, it.heard, it.written, it.folderID?.let { f -> FolderIDBox(f.rawValue) }) }
        defaults.setString(KEY, json.encodeToString(serializer, records))
    }
}

/**
 * The entries for a recording in this folder. When a folder spells a word its own way, that spelling replaces the
 * global one instead of running after it, so that "ana" never becomes "Ana Paula" and then "Anna Paula".
 */
fun List<VocabularyEntry>.applying(folder: FolderID?): List<VocabularyEntry> {
    val local = filter { folder != null && it.folderID == folder }
    val overridden = local.map { it.key }.toSet()
    return local + filter { it.folderID == null && it.key !in overridden }
}

/** Corrects text after transcription, which works with every engine. */
object VocabularyCorrector {
    fun apply(entries: List<VocabularyEntry>, text: String): String =
        entries.filter { it.isValid }.fold(text) { result, entry -> replace(entry.heard, entry.written, result) }

    /**
     * Whole words only, so that "ana" never changes "banana". Text with no spaces between words, such as Japanese,
     * has no boundaries to look for, so it matches anywhere.
     */
    private fun replace(heard: String, written: String, text: String): String {
        val needle = heard.trimmedWhitespace()
        val usesWords = needle.codePoints().allMatch { !isCJK(it) }
        val folded = FoldedText(text)
        val result = StringBuilder()
        var rest = 0
        while (true) {
            val range = folded.find(needle, rest) ?: break
            val startsWord = range.first == 0 || !Character.isLetter(text.codePointBefore(range.first))
            val endsWord = range.last + 1 == text.length || !Character.isLetter(text.codePointAt(range.last + 1))
            result.append(text, rest, range.first)
            result.append(if (!usesWords || (startsWord && endsWord)) written else text.substring(range.first, range.last + 1))
            rest = range.last + 1
            if (range.isEmpty()) break
        }
        return result.append(text, rest, text.length).toString()
    }

    private fun isCJK(codePoint: Int): Boolean = codePoint in 0x3040..0x30FF || codePoint in 0x4E00..0x9FFF
}

/**
 * Removes hesitations for reading. It works on what is shown and never on what is stored, so the original is always
 * one tap away and evidence links keep pointing at the real words.
 */
object TranscriptPolish {
    private val spaced = listOf("um", "umm", "uh", "uhh", "erm", "hmm", "ãh", "éé", "hum", "eh", "ehh")
    private val unspaced = listOf("えーと", "えっと", "あのー", "えー")

    fun polish(text: String): String {
        var result = text
        for (filler in unspaced) result = result.replace(filler, "")
        val words = result.split(" ").filter { it.isNotEmpty() }.filter { word ->
            word.lowercase().trim { isPunctuation(it) } !in spaced
        }
        // Punctuation left behind by a hesitation at the start reads as a mistake.
        val cleaned = words.joinToString(" ").trim { it.isWhitespace() || (isPunctuation(it) && it != '"' && it != '\'') }
        // A phrase that was only hesitation stays as it was: an empty line would hide that someone spoke.
        if (cleaned.isEmpty()) return text
        val first = cleaned.codePointAt(0)
        return String(Character.toChars(first)).uppercase() + cleaned.substring(Character.charCount(first))
    }

    /** Foundation's punctuation set: the Unicode P categories. */
    internal fun isPunctuation(char: Char): Boolean = when (Character.getType(char).toByte()) {
        Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION,
        Character.END_PUNCTUATION, Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION,
        Character.OTHER_PUNCTUATION -> true
        else -> false
    }
}
