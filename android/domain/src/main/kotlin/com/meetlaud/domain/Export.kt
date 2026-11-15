package com.meetlaud.domain

enum class TranscriptFormat(val fileExtension: String) {
    TXT("txt"), MARKDOWN("md"), SRT("srt"), VTT("vtt");

    val usesOptions: Boolean get() = this == TXT || this == MARKDOWN
}

data class ExportOptions(val includesSpeakers: Boolean = true, val includesTimestamps: Boolean = true)

/** Turns a transcript into a file. Subtitle formats always carry times, because they are made of them. */
object TranscriptExporter {
    fun text(title: String, segments: List<TranscriptSegment>, speakers: List<Speaker>, format: TranscriptFormat, options: ExportOptions = ExportOptions()): String =
        when (format) {
            TranscriptFormat.TXT -> lines(segments, speakers, options).joinToString("\n") + "\n"
            TranscriptFormat.MARKDOWN -> "# $title\n\n" + lines(segments, speakers, options, bold = true).joinToString("\n\n") + "\n"
            TranscriptFormat.SRT -> segments.mapIndexed { index, segment ->
                val time = "${stamp(segment.start, ",")} --> ${stamp(segment.end, ",")}"
                "${index + 1}\n$time\n${cue(segment, speakers, options)}\n"
            }.joinToString("\n")
            TranscriptFormat.VTT -> "WEBVTT\n\n" + segments.joinToString("\n") { segment ->
                val time = "${stamp(segment.start, ".")} --> ${stamp(segment.end, ".")}"
                "$time\n${cue(segment, speakers, options)}\n"
            }
        }

    private fun name(segment: TranscriptSegment, speakers: List<Speaker>): String? =
        TranscriptFormatter.displayName(speakers.firstOrNull { it.id.uuidString == segment.speaker })

    private fun cue(segment: TranscriptSegment, speakers: List<Speaker>, options: ExportOptions): String {
        // A line break inside a cue is legal, and a blank line would end it early.
        val text = segment.text.nonEmptyLines().joinToString(" ")
        val name = name(segment, speakers)
        return if (options.includesSpeakers && name != null) "$name: $text" else text
    }

    private fun lines(segments: List<TranscriptSegment>, speakers: List<Speaker>, options: ExportOptions, bold: Boolean = false): List<String> =
        segments.map { segment ->
            var prefix = if (options.includesTimestamps) "[${clock(segment.start)}] " else ""
            val name = name(segment, speakers)
            if (options.includesSpeakers && name != null) prefix += if (bold) "**$name:** " else "$name: "
            prefix + segment.text
        }

    fun clock(time: TimeInterval): String {
        val total = maxOf(0.0, time).toInt()
        val hours = total / 3600
        val minutes = total / 60 % 60
        val seconds = total % 60
        return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, seconds) else "%02d:%02d".format(minutes, seconds)
    }

    private fun stamp(time: TimeInterval, separator: String): String {
        val milliseconds = Math.round(maxOf(0.0, time) * 1000).toInt()
        val hours = milliseconds / 3_600_000
        val minutes = milliseconds / 60000 % 60
        val seconds = milliseconds / 1000 % 60
        val rest = milliseconds % 1000
        return "%02d:%02d:%02d%s%03d".format(hours, minutes, seconds, separator, rest)
    }
}

object SummaryExporter {
    fun markdown(title: String, summary: Summary, speakers: List<Speaker>): String {
        val result = StringBuilder("# $title\n\n")
        for (section in summary.sections) {
            result.append("## ${section.title}\n\n")
            for (item in section.items) result.append(line(item, section.kind, speakers)).append("\n")
            result.append("\n")
        }
        return result.toString()
    }

    private fun line(item: SummaryItem, kind: SectionKind, speakers: List<Speaker>): String {
        var text = SpeakerTokens.decode(item.text, speakers)
        item.owner?.let { text = "${SpeakerTokens.decode(it, speakers)}: $text" }
        item.due?.let { text += " ($it)" }
        item.sourceTime?.let { text += " [${TranscriptExporter.clock(it)}]" }
        return when (kind) {
            SectionKind.BULLETS -> "- $text"
            SectionKind.TASKS -> "- [${if (item.isDone) "x" else " "}] $text"
        }
    }
}

/** A title can hold anything, and a file name cannot. */
object ExportFileName {
    private val banned = "/\\:?%*|\"<>".toSet()

    fun safe(title: String, fileExtension: String): String {
        val cleaned = buildString {
            title.codePoints().forEach {
                val isBanned = (it < 0x10000 && it.toChar() in banned) || Character.getType(it) == Character.CONTROL.toInt() ||
                    it == '\n'.code || it == '\r'.code || it == 0x2028 || it == 0x2029 || it == 0x85
                if (isBanned) append(' ') else appendCodePoint(it)
            }
        }.trim { it == ' ' || it == '\t' || it == '.' || Character.isSpaceChar(it) }
        val name = if (cleaned.isEmpty()) "Meeting" else cleaned.prefixCharacters(80)
        return "$name.$fileExtension"
    }
}
