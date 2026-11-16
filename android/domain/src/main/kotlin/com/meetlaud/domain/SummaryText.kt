package com.meetlaud.domain

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlin.math.abs

/** Swift's `split(whereSeparator: \.isNewline)`: lines, with empty ones left out. */
internal fun String.nonEmptyLines(): List<String> = split('\n', '\r', '\u000B', '\u000C', '\u0085', '\u2028', '\u2029').filter { it.isNotEmpty() }

/** Trims spaces and tabs, as `trimmingCharacters(in: .whitespaces)`. */
internal fun String.trimSpaces(): String = trim { it == ' ' || it == '\t' || it == ' ' || Character.isSpaceChar(it) && it != '\n' }

/** A rough token count. Models count Japanese close to one token per character, and Latin text near four per token. */
object TokenEstimator {
    fun tokens(text: String): Int {
        var latin = 0
        var wide = 0
        text.codePoints().forEach { if (it > 0x2E7F) wide += 1 else latin += 1 }
        return wide + latin / 4 + 1
    }
}

/** Turns a transcript into the lines a model reads, and into pieces that fit its context. */
object TranscriptFormatter {
    fun displayName(speaker: Speaker?): String? = speaker?.let { it.name ?: "Speaker ${it.number}" }

    /** `[75] Ana: Let us start.` The number is how a claim finds its way back to the audio. */
    fun lines(segments: List<TranscriptSegment>, speakers: List<Speaker>): List<String> = segments.map { segment ->
        val speaker = speakers.firstOrNull { it.id.uuidString == segment.speaker }
        val prefix = displayName(speaker)?.let { "$it: " } ?: ""
        "[${segment.start.toInt()}] $prefix${segment.text}"
    }

    fun chunks(lines: List<String>, limit: Int): List<List<String>> {
        val result = mutableListOf<List<String>>()
        var current = mutableListOf<String>()
        var size = 0
        for (line in lines) {
            val tokens = TokenEstimator.tokens(line)
            if (size + tokens > limit && current.isNotEmpty()) {
                result.add(current)
                current = mutableListOf()
                size = 0
            }
            current.add(line)
            size += tokens
        }
        if (current.isNotEmpty()) result.add(current)
        return result
    }
}

/** Reads what the model wrote. Models drift from any format, so this accepts what it reasonably can and never throws. */
object SummaryParser {
    fun items(text: String, kind: SectionKind): List<SummaryItem> {
        val items = text.nonEmptyLines().mapNotNull { item(it, kind) }
        // Models overrun a limit in a prompt and repeat themselves, and they list the most important first when asked.
        return unique(items).take(SummaryLimits.limit(kind))
    }

    /** Keeps the first of items that say the same thing. */
    internal fun unique(items: List<SummaryItem>): List<SummaryItem> {
        val seen = HashSet<String>()
        return items.filter { seen.add(normalized(it.text)) }
    }

    private fun normalized(text: String): String = buildString {
        text.lowercase().codePoints().forEach { if (Character.isLetter(it) || isNumber(it)) appendCodePoint(it) }
    }

    /**
     * Combines the items from each part of a long meeting, taking one from each in turn. A model reading a whole
     * meeting at once favors how it ended, and a summary has to cover the start too.
     */
    fun balanced(parts: List<List<SummaryItem>>, kind: SectionKind): List<SummaryItem> {
        val taken = mutableListOf<SummaryItem>()
        var depth = 0
        while (parts.any { it.size > depth }) {
            taken += parts.mapNotNull { it.getOrNull(depth) }
            depth += 1
        }
        val kept = unique(taken).take(SummaryLimits.limit(kind))
        // Chosen by turn, and read in the order things happened.
        return kept.sortedBy { it.sourceTime ?: Double.POSITIVE_INFINITY }
    }

    /** An item written back in the format the model reads, to hand it to the model again. */
    fun line(item: SummaryItem, kind: SectionKind): String {
        val time = item.sourceTime?.let { "[${it.toInt()}] " } ?: ""
        if (kind != SectionKind.TASKS) return time + item.text
        return "$time${item.owner ?: "-"} | ${item.text} | ${item.due ?: "-"}"
    }

    /** Notes keep their `[seconds]`, and lose everything around it. */
    fun notes(text: String): List<String> = text.nonEmptyLines().mapNotNull { line ->
        val cleaned = cleanBullet(line)
        val (time, rest) = splitTime(cleaned)
        if (rest.isEmpty()) null else time?.let { "[${it.toInt()}] $rest" } ?: rest
    }

    private fun item(line: String, kind: SectionKind): SummaryItem? {
        val cleaned = cleanBullet(line)
        if (isHeading(cleaned)) return null
        val (time, written) = splitTime(cleaned)
        val rest = withoutEchoedFormat(written)
        // A model stuck in a loop writes the same words over and over, and nothing in such a line can be trusted.
        if (rest.isEmpty() || isPlaceholder(rest) || TranscriptCleanup.markRepeats(rest) != rest) return null

        if (kind != SectionKind.TASKS) return SummaryItem(text = rest, sourceTime = time)

        // Swift's split drops empty pieces, so "|a|" counts two columns, not four.
        var parts = rest.split("|").filter { it.isNotEmpty() }.map { it.trimSpaces() }
        // A model sometimes echoes the format, and writes the real owner in the next column.
        if (parts.size > 3 && isPlaceholder(parts[0])) parts = parts.drop(1)
        if (parts.size < 2) return SummaryItem(text = rest, sourceTime = time)
        return SummaryItem(
            text = parts[1],
            sourceTime = time,
            owner = unknownToNull(parts[0]),
            due = if (parts.size > 2) unknownToNull(parts[2]) else null,
        )
    }

    private fun unknownToNull(text: String): String? {
        val cleaned = text.trim { it in " -–—" }
        return if (cleaned.isEmpty() || isPlaceholder(cleaned)) null else cleaned
    }

    /** The names of the columns in the prompt, which are not an answer. */
    private fun isPlaceholder(text: String): Boolean =
        text.lowercase() in setOf("owner", "task", "due date", "date", "unknown", "none", "n/a", "item", "note")

    /** The prompt says "[seconds] item", and a small model sometimes starts each line with "Item:". */
    private fun withoutEchoedFormat(text: String): String {
        for (word in listOf("Item:", "item:", "Note:", "note:")) {
            if (text.startsWith(word)) return text.substring(word.length).trimSpaces()
        }
        return text
    }

    private fun cleanBullet(line: String): String {
        var text = line.trimSpaces()
        while (text.isNotEmpty() && text[0] in "-*•・") text = text.substring(1).trimSpaces()
        return text.replace("**", "")
    }

    private fun isHeading(line: String): Boolean =
        line.startsWith("#") || line.startsWith("|") || (line.endsWith(":") && line.codePointCount(0, line.length) < 40)

    /** Accepts `[75]`, `[75.2]`, and `[1:15]`. */
    private fun splitTime(line: String): Pair<TimeInterval?, String> {
        val close = line.indexOf(']')
        if (!line.startsWith("[") || close < 0) return null to line
        val inside = line.substring(1, close)
        val rest = line.substring(close + 1).trimSpaces()
        val pieces = inside.split(":").filter { it.isNotEmpty() }
        val parts = pieces.mapNotNull { it.toDoubleOrNull() }
        if (parts.isEmpty() || parts.size != pieces.size) return null to line
        return parts.fold(0.0) { sum, value -> sum * 60 + value } to rest
    }
}

/** Ties a model's claims back to the transcript, because models state wrong things with total confidence. */
object SummaryValidator {
    /**
     * Numbers can always be checked. Words only when the summary is in the meeting's language: a translated "Friday"
     * would not be found in the transcript, and it may well have been said.
     */
    internal fun isSaid(due: String, segments: List<TranscriptSegment>, sameLanguage: Boolean): Boolean {
        val numbers = splitRuns(due) { isNumber(it) }
        if (numbers.isNotEmpty()) return numbers.all { number -> segments.any { it.text.contains(number) } }
        if (!sameLanguage) return true
        val words = splitRuns(due) { Character.isLetter(it) }
        return words.any { word -> segments.any { it.text.caseInsensitiveContains(word) } }
    }

    private fun splitRuns(text: String, keep: (Int) -> Boolean): List<String> {
        val result = mutableListOf<String>()
        val current = StringBuilder()
        text.codePoints().forEach {
            if (keep(it)) current.appendCodePoint(it) else if (current.isNotEmpty()) { result.add(current.toString()); current.clear() }
        }
        if (current.isNotEmpty()) result.add(current.toString())
        return result
    }

    /** The example from the prompt, copied as if someone had said it. A meeting that really was about it keeps it. */
    fun isEchoedExample(item: SummaryItem, segments: List<TranscriptSegment>): Boolean =
        item.text in SummaryPrompts.exampleTasks && segments.none { it.text.caseInsensitiveContains(item.text) }

    /** How far a citation can sit from a real phrase. */
    internal const val TOLERANCE: TimeInterval = 10.0

    fun validate(item: SummaryItem, segments: List<TranscriptSegment>, speakers: List<Speaker>, sameLanguage: Boolean = true): SummaryItem {
        val source = item.sourceTime?.let { closest(it, segments) }
        // A citation that points at nothing is worse than none: the link would look like proof.
        var result = item.copy(sourceTime = source?.start)
        // Models fill an empty date with a plausible one, and a wrong deadline is worse than none.
        result.due?.let { if (!isSaid(it, segments, sameLanguage)) result = result.copy(due = null) }
        result = result.copy(needsReview = source == null)

        result.owner?.let { owner ->
            val known = speakers.mapNotNull { TranscriptFormatter.displayName(it) }
            val transcriptNames = segments.any { it.text.caseInsensitiveContains(owner) }
            if (known.none { it.equals(owner, ignoreCase = true) } && !transcriptNames) result = result.copy(needsReview = true)
        }
        return result
    }

    private fun closest(time: TimeInterval, segments: List<TranscriptSegment>): TranscriptSegment? =
        segments
            .filter { abs(it.start - time) <= TOLERANCE || (it.start <= time && time <= it.end) }
            .minByOrNull { abs(it.start - time) }
}

/**
 * Stores speakers as tokens, so that renaming someone later reaches summaries that are already written. A token also
 * keeps the name it replaced, for when the speaker it points at is gone.
 */
object SpeakerTokens {
    private val tokenPattern = Regex("\\{\\{speaker:([0-9A-Fa-f-]+)\\|([^}]*)\\}\\}")

    fun encode(text: String, speakers: List<Speaker>): String {
        val named = speakers.mapNotNull { speaker -> TranscriptFormatter.displayName(speaker)?.let { it to speaker } }
            .sortedByDescending { it.first.codePointCount(0, it.first.length) }
        if (named.isEmpty()) return text
        // One pass, longest first: "Ana Lima" must not become a token for "Ana", or "Speaker 10" for "Speaker 1".
        // The edges only look at Latin letters and digits, because Japanese has no spaces between words.
        val names = named.joinToString("|") { Regex.escape(it.first) }
        val pattern = Regex("(?<![\\p{IsLatin}\\p{Nd}])(?:$names)(?![\\p{IsLatin}\\p{Nd}])")
        return pattern.replace(text) { match ->
            val found = named.firstOrNull { it.first == match.value } ?: return@replace match.value
            "{{speaker:${found.second.id.uuidString}|${found.first}}}"
        }
    }

    fun decode(text: String, speakers: List<Speaker>, name: (Speaker) -> String? = { TranscriptFormatter.displayName(it) }): String =
        tokenPattern.replace(text) { match ->
            speakers.firstOrNull { it.id.uuidString.equals(match.groupValues[1], ignoreCase = true) }?.let(name)
                ?: match.groupValues[2]
        }
}

class TemplateException : Exception("invalid")

/** The rules for a template, and its file format. Files come from other people, so nothing in them is trusted. */
object TemplateCodec {
    object Limits {
        const val NAME = 80
        const val INSTRUCTIONS = 2000
        const val SECTIONS = 12
    }

    /** Keys in alphabetical order, as the iOS app writes them with `.sortedKeys`. */
    @Serializable
    private data class FileFormat(
        val category: TemplateCategory,
        val instructions: String,
        val name: String,
        val schemaVersion: Int,
        val sections: List<TemplateSection>,
    )

    private const val SCHEMA_VERSION = 1
    private val reader = Json { ignoreUnknownKeys = true }
    private val writer = Json { prettyPrint = true; encodeDefaults = true }

    private fun length(text: String) = text.codePointCount(0, text.length)

    fun isValid(template: SummaryTemplate): Boolean {
        val name = template.name.trimmedWhitespace()
        return name.isNotEmpty() && length(name) <= Limits.NAME &&
            length(template.instructions) <= Limits.INSTRUCTIONS &&
            template.sections.size in 1..Limits.SECTIONS &&
            template.sections.all { section ->
                val title = section.title.trimmedWhitespace()
                title.isNotEmpty() && length(title) <= Limits.NAME
            }
    }

    fun encode(template: SummaryTemplate): ByteArray =
        writer.encodeToString(FileFormat.serializer(), FileFormat(template.category, template.instructions, template.name, SCHEMA_VERSION, template.sections))
            .encodeToByteArray()

    /** Always a new user template: a file can neither replace an existing one nor pass for a built-in. */
    fun decode(data: ByteArray): SummaryTemplate {
        val file = runCatching { reader.decodeFromString(FileFormat.serializer(), data.decodeToString()) }.getOrNull()
        if (file == null || file.schemaVersion != SCHEMA_VERSION) throw TemplateException()
        val template = SummaryTemplate(name = file.name, category = file.category, instructions = file.instructions, sections = file.sections)
        if (!isValid(template)) throw TemplateException()
        return template
    }

    /** Reads what a model wrote when asked to design a template. */
    fun parseDraft(text: String): SummaryTemplate {
        var name = ""
        var instructions = ""
        val sections = mutableListOf<TemplateSection>()
        for (line in text.nonEmptyLines()) {
            val parts = line.replace("**", "").split(":", limit = 2)
            if (parts.size != 2) continue
            val value = parts[1].trimSpaces()
            when (parts[0].trim { it in " -*#" }.lowercase()) {
                "name" -> name = value.prefixCharacters(Limits.NAME)
                "instructions" -> instructions = value.prefixCharacters(Limits.INSTRUCTIONS)
                "section" -> sections.add(TemplateSection(value.prefixCharacters(Limits.NAME)))
                "task section" -> sections.add(TemplateSection(value.prefixCharacters(Limits.NAME), SectionKind.TASKS))
            }
        }
        val template = SummaryTemplate(name = name, category = TemplateCategory.GENERAL, instructions = instructions, sections = sections.take(Limits.SECTIONS))
        if (!isValid(template)) throw TemplateException()
        return template
    }
}

object SummaryPreferences {
    const val AUTO_KEY = "summary.auto"
    const val PROFILE_KEY = "ai.profile"
    const val DEFAULT_TEMPLATE_KEY = "summary.defaultTemplate"
    const val PROFILE_LIMIT = 1500
}
