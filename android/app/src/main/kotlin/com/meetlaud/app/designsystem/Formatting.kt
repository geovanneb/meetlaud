package com.meetlaud.app.designsystem

import java.text.DecimalFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.floor
import com.meetlaud.app.localization.Strings

/** `12:04`, or `1:12:04` past an hour. Used wherever a time position appears. */
val Double.clock: String
    get() {
        val total = floor(maxOf(this, 0.0)).toLong()
        val hours = total / 3600
        val minutes = (total % 3600) / 60
        val seconds = total % 60
        return if (this >= 3600) "%d:%02d:%02d".format(hours, minutes, seconds) else "%d:%02d".format(minutes, seconds)
    }

/** `1.2 GB`, in decimal units as iOS's file byte count style. */
val Long.fileSize: String
    get() {
        if (this < 1000) return if (this == 0L) "Zero KB" else "$this bytes"
        val units = listOf("KB", "MB", "GB", "TB")
        var value = this / 1000.0
        var index = 0
        while (value >= 1000 && index < units.lastIndex) {
            value /= 1000
            index++
        }
        val format = if (index == 0) DecimalFormat("#,##0") else DecimalFormat("#,##0.#")
        return "${format.format(value)} ${units[index]}"
    }

/**
 * "Nov 8, 2026 at 8:57", as Date.formatted(date: .abbreviated, time: .shortened). The time follows the phone's
 * 12- or 24-hour setting, as iOS follows the region's.
 */
fun Instant.abbreviatedDateTime(locale: Locale = Strings.locale()): String {
    val zoned = atZone(ZoneId.systemDefault())
    val date = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).format(zoned)
    return when (locale.language) {
        "en" -> "$date at ${shortTime(locale)}"
        "pt" -> "$date às ${shortTime(locale)}"
        "es" -> "$date, ${shortTime(locale)}"
        else -> "$date ${shortTime(locale)}"
    }
}

/** "8:57" or "8:57 PM", by the phone's clock setting. */
fun Instant.shortTime(locale: Locale = Strings.locale()): String {
    val pattern = if (Strings.uses24HourClock()) "H:mm" else "h:mm a"
    return DateTimeFormatter.ofPattern(pattern, locale).withZone(ZoneId.systemDefault()).format(this)
}

/** "Today at 15:00", "Tomorrow at 9:00", or the date, as a DateFormatter with relative formatting. */
fun Instant.relativeSchedule(locale: Locale = Strings.locale()): String {
    val zone = ZoneId.systemDefault()
    val day = atZone(zone).toLocalDate()
    val today = java.time.LocalDate.now(zone)
    val dayText = when (day) {
        today -> android.text.format.DateUtils.getRelativeTimeSpanString(toEpochMilli(), System.currentTimeMillis(), android.text.format.DateUtils.DAY_IN_MILLIS).toString()
        today.plusDays(1), today.minusDays(1) -> android.text.format.DateUtils.getRelativeTimeSpanString(toEpochMilli(), System.currentTimeMillis(), android.text.format.DateUtils.DAY_IN_MILLIS).toString()
        else -> DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).format(atZone(zone))
    }
    return when (locale.language) {
        "en" -> "$dayText at ${shortTime(locale)}"
        "pt" -> "$dayText às ${shortTime(locale)}"
        else -> "$dayText, ${shortTime(locale)}"
    }
}

/** A date in the locale's own order for the given fields, as Date.formatted(.dateTime...) picks it. Skeleton: "MMMy", "d", "MMMMy". */
fun java.time.LocalDate.formatted(skeleton: String, locale: Locale = Strings.locale()): String =
    DateTimeFormatter.ofPattern(android.text.format.DateFormat.getBestDateTimePattern(locale, skeleton), locale).format(this)

fun java.time.LocalDate.completeDate(locale: Locale = Strings.locale()): String =
    DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL).withLocale(locale).format(this)
