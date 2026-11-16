package com.meetlaud.domain

import java.text.Collator
import java.time.Instant
import java.util.Locale
import java.util.UUID

@JvmInline
value class FolderID(val rawValue: UUID = UUID.randomUUID()) {
    override fun toString(): String = rawValue.toString().uppercase()

    companion object {
        fun from(string: String): FolderID? = parseUUID(string)?.let(::FolderID)
    }
}

data class Folder(
    val id: FolderID = FolderID(),
    val name: String,
    val createdAt: Instant,
)

enum class RecordingSort(val raw: String) {
    NEWEST("newest"), OLDEST("oldest"), NAME("name"), LONGEST("longest");

    fun sorted(recordings: List<Recording>): List<Recording> = when (this) {
        NEWEST -> recordings.sortedByDescending { it.createdAt }
        OLDEST -> recordings.sortedBy { it.createdAt }
        NAME -> recordings.sortedWith { a, b -> localizedStandardCompare(a.title, b.title) }
        LONGEST -> recordings.sortedByDescending { it.duration }
    }

    companion object {
        fun from(raw: String): RecordingSort? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * Finder-like ordering, as Foundation's localizedStandardCompare: case and accents matter less than letters, and
 * runs of digits compare as numbers, so "Meeting 2" comes before "Meeting 10".
 */
fun localizedStandardCompare(a: String, b: String, locale: Locale = Locale.getDefault()): Int {
    val collator = Collator.getInstance(locale).apply { strength = Collator.SECONDARY }
    val left = Regex("\\d+|\\D+").findAll(a).map { it.value }.toList()
    val right = Regex("\\d+|\\D+").findAll(b).map { it.value }.toList()
    for (index in 0 until minOf(left.size, right.size)) {
        val l = left[index]
        val r = right[index]
        val result = if (l[0].isDigit() && r[0].isDigit()) {
            l.toBigInteger().compareTo(r.toBigInteger())
        } else {
            collator.compare(l, r)
        }
        if (result != 0) return result
    }
    return left.size.compareTo(right.size)
}

/** A place in a recording that matches a search. `time` is null when the match is the recording itself. */
data class SearchHit(
    val id: UUID = UUID.randomUUID(),
    val recording: Recording,
    val time: TimeInterval? = null,
    val excerpt: String? = null,
)

data class CalendarEvent(
    val id: String,
    val title: String,
    val start: Instant,
    val end: Instant,
    val attendees: List<String>,
    /** The calendar it comes from, so that the person can leave a calendar out. */
    val calendarID: String = "",
) {
    /**
     * Whether the event says anything. Busy blocks from shared calendars arrive with no title and no people, and
     * there is nothing to show or to record about them.
     */
    val hasDetails: Boolean get() = hasTitle || attendees.isNotEmpty()
    val hasTitle: Boolean get() = title.isNotBlank()
}

enum class AppTheme(val raw: String) {
    SYSTEM("system"), LIGHT("light"), DARK("dark");

    companion object {
        fun from(raw: String?): AppTheme = entries.firstOrNull { it.raw == raw } ?: SYSTEM
    }
}

object ThemePreferences {
    const val KEY = "appearance.theme"
}

object WidgetPreferences {
    /** Off by default: a meeting's name on the Home Screen can be seen by anyone holding the phone. */
    const val SHOW_CONTENT_KEY = "widgets.showContent"
}

enum class CalendarAccess { UNDETERMINED, GRANTED, DENIED }
