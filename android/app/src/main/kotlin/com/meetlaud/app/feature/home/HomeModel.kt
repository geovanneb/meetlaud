package com.meetlaud.app.feature.home

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.meetlaud.domain.CalendarAccess
import com.meetlaud.domain.CalendarChoices
import com.meetlaud.domain.CalendarEvent
import com.meetlaud.domain.CalendarGrid
import com.meetlaud.domain.CalendarProvider
import com.meetlaud.domain.Recording
import com.meetlaud.domain.RecordingStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

/** Home's state, as HomeModel.swift. */
class HomeModel(store: RecordingStore, private val calendar: CalendarProvider, private val choices: CalendarChoices, scope: CoroutineScope) {
    var recordings by mutableStateOf<List<Recording>>(emptyList())
        private set
    var events by mutableStateOf<List<CalendarEvent>>(emptyList())
        private set
    var calendarAccess by mutableStateOf(calendar.access)
        private set
    /** Closed Connect card: Upcoming shows a line that leads to Settings instead. */
    var isConnectHidden by mutableStateOf(choices.isConnectHidden)
        private set
    var calendarEvents by mutableStateOf<List<CalendarEvent>>(emptyList())
        private set

    init {
        scope.launch { store.observeRecordings().collect { all -> recordings = all.filter { it.deletedAt == null } } }
    }

    suspend fun refreshEvents() {
        calendarAccess = calendar.access
        isConnectHidden = choices.isConnectHidden
        val now = Instant.now()
        events = calendar.events(now, now.plus(Duration.ofDays(7))).filter { it.hasDetails }
    }

    fun hideConnect() {
        choices.isConnectHidden = true
        isConnectHidden = true
    }

    suspend fun connectCalendar() {
        calendar.requestAccess()
        refreshEvents()
    }

    /** What Home shows in Upcoming. The full week lives in Calendar view. */
    val nextEvents: List<CalendarEvent> get() = events.take(3)

    // MARK: - Calendar view

    /** Everything the month's grid can show, neighbors included, so that a day is ready as soon as it is tapped. */
    suspend fun loadCalendar(month: LocalDate) {
        val grid = CalendarGrid.month(month, Locale.getDefault())
        val zone = ZoneId.systemDefault()
        calendarEvents = calendar.events(grid.first().atStartOfDay(zone).toInstant(), grid.last().plusDays(1).atStartOfDay(zone).toInstant())
            .filter { it.hasDetails }
    }

    private fun Instant.day(): LocalDate = atZone(ZoneId.systemDefault()).toLocalDate()

    fun events(day: LocalDate): List<CalendarEvent> = calendarEvents.filter { it.start.day() == day }

    fun recordings(day: LocalDate): List<Recording> = recordings.filter { it.createdAt.day() == day }.sortedBy { it.createdAt }

    fun hasContent(day: LocalDate): Boolean = events(day).isNotEmpty() || recordings(day).isNotEmpty()
}
