package com.meetlaud.domain

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.TextStyle
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import java.time.Instant
import java.util.Locale

/** One calendar on the device, such as "Work" in an Exchange account. */
data class CalendarSource(
    val id: String,
    val title: String,
    /** The account that holds it, as the system names it. */
    val account: String,
    /** Two accounts can share a name, so calendars are grouped by this. */
    val accountID: String = account,
    val tint: Tint? = null,
) {
    data class Tint(val red: Double, val green: Double, val blue: Double)
}

/**
 * Which calendars the person wants the app to use. Kept on the device. It stores the calendars that are off, so
 * that a calendar added later shows up without a visit to Settings.
 */
class CalendarChoices(private val defaults: Preferences) {
    companion object {
        const val IS_OFF_KEY = "calendars.isOff"
        const val HIDDEN_KEY = "calendars.hidden"
        const val CONNECT_HIDDEN_KEY = "calendars.connectHidden"
    }

    /** The one switch: with it off, the app reads no calendar at all. */
    var isOn: Boolean
        get() = defaults.bool(IS_OFF_KEY) != true
        set(value) = defaults.setBool(IS_OFF_KEY, !value)

    /** The person closed Home's Connect card, or turned calendars off in Settings. */
    var isConnectHidden: Boolean
        get() = defaults.bool(CONNECT_HIDDEN_KEY) == true
        set(value) = defaults.setBool(CONNECT_HIDDEN_KEY, value)

    val hidden: Set<String> get() = defaults.stringList(HIDDEN_KEY)?.toSet() ?: emptySet()

    fun isShown(id: String): Boolean = id !in hidden

    fun setShown(isShown: Boolean, id: String) {
        val hidden = hidden.toMutableSet()
        if (isShown) hidden.remove(id) else hidden.add(id)
        defaults.setStringList(HIDDEN_KEY, hidden.sorted())
    }
}

/** The device's calendars, narrowed to what the person chose. Everything that shows events reads through this. */
class ChosenCalendars(private val base: CalendarProvider, private val choices: CalendarChoices) : CalendarProvider {
    /** Turned off in the app reads as not connected, so Home offers Connect again. */
    override val access: CalendarAccess get() = if (choices.isOn) base.access else CalendarAccess.UNDETERMINED

    override suspend fun requestAccess(): Boolean {
        choices.isOn = true
        return base.requestAccess()
    }

    override suspend fun events(from: Instant, to: Instant): List<CalendarEvent> {
        if (!choices.isOn) return emptyList()
        val hidden = choices.hidden
        return base.events(from, to).filter { it.calendarID !in hidden }
    }

    override suspend fun calendars(): List<CalendarSource> = base.calendars()
}

/** The days a calendar shows. The week starts where the person's region starts it. */
object CalendarGrid {
    const val DAYS_IN_WEEK = 7
    /** Always six rows, so that the page does not change height between months. */
    const val DAYS_IN_MONTH_GRID = 42

    fun week(containing: LocalDate, locale: Locale): List<LocalDate> = days(startOfWeek(containing, locale), DAYS_IN_WEEK)

    fun month(containing: LocalDate, locale: Locale): List<LocalDate> =
        days(startOfWeek(startOfMonth(containing), locale), DAYS_IN_MONTH_GRID)

    fun startOfMonth(containing: LocalDate): LocalDate = containing.withDayOfMonth(1)

    /** The first day of each month from `before` months ago to `after` months ahead. */
    fun months(around: LocalDate, before: Int, after: Int): List<LocalDate> {
        val start = startOfMonth(around)
        return (-before..after).map { start.plusMonths(it.toLong()) }
    }

    /** One letter per day, in the order of the grid. */
    fun weekdayLetters(locale: Locale): List<String> {
        val first = WeekFields.of(locale).firstDayOfWeek
        return (0 until 7).map { first.plus(it.toLong()).getDisplayName(TextStyle.NARROW_STANDALONE, locale) }
    }

    fun firstWeekday(locale: Locale): DayOfWeek = WeekFields.of(locale).firstDayOfWeek

    private fun startOfWeek(date: LocalDate, locale: Locale): LocalDate =
        date.with(TemporalAdjusters.previousOrSame(firstWeekday(locale)))

    /** By calendar days and not by seconds, because a day is not always 24 hours long. */
    private fun days(start: LocalDate, count: Int): List<LocalDate> = (0 until count).map { start.plusDays(it.toLong()) }
}
