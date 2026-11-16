package com.meetlaud.app.feature.home

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.EmptyState
import com.meetlaud.app.designsystem.Motion
import com.meetlaud.app.designsystem.PrimaryAction
import com.meetlaud.app.designsystem.PromptBar
import com.meetlaud.app.designsystem.SfIcon
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.designsystem.TapTarget
import com.meetlaud.app.designsystem.TextAction
import com.meetlaud.app.designsystem.completeDate
import com.meetlaud.app.designsystem.formatted
import com.meetlaud.app.designsystem.RowDivider
import com.meetlaud.app.feature.shared.RecordingRow
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.localization.Strings
import com.meetlaud.app.routing.AppRoute
import com.meetlaud.app.routing.LocalRouter
import com.meetlaud.app.shell.Screen
import com.meetlaud.domain.CalendarAccess
import com.meetlaud.domain.CalendarEvent
import com.meetlaud.domain.CalendarGrid
import com.meetlaud.domain.Recording
import com.meetlaud.domain.RecordingStatus
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate

private const val MONTHS_AROUND = 18

private sealed interface AgendaItem {
    val key: String
    val start: Instant

    data class Event(val event: CalendarEvent) : AgendaItem {
        override val key get() = "event-${event.id}"
        override val start: Instant get() = event.start
    }

    data class Meeting(val recording: Recording) : AgendaItem {
        override val key get() = "recording-${recording.id.rawValue}"
        override val start: Instant get() = recording.createdAt
    }
}

/** A week that opens into a month, with the chosen day's meetings below it. As CalendarView.swift. */
@Composable
fun CalendarScreen(model: HomeModel, onRecordEvent: (CalendarEvent) -> Unit) {
    val router = LocalRouter.current
    val scope = rememberCoroutineScope()
    val locale = Strings.locale()
    var selected by remember { mutableStateOf(LocalDate.now()) }
    var isExpanded by remember { mutableStateOf(false) }
    val days = if (isExpanded) CalendarGrid.month(selected, locale) else CalendarGrid.week(selected, locale)
    val visibleMonth = CalendarGrid.startOfMonth(selected)
    LaunchedEffect(visibleMonth) { model.loadCalendar(visibleMonth) }

    /** Today, in the month it is in. Otherwise the month's first day. */
    fun choose(month: LocalDate) {
        val today = LocalDate.now()
        selected = if (today.year == month.year && today.month == month.month) today else month
    }

    Screen(
        modifier = Modifier.testTag("screen.calendar"),
        leading = {
            val turn by animateFloatAsState(if (isExpanded) 180f else 0f, Motion.standard(), label = "chevron")
            Row(
                Modifier
                    .heightIn(min = TapTarget)
                    .clickable(remember { MutableInteractionSource() }, indication = null) { isExpanded = !isExpanded }
                    .semantics { role = Role.Button; stateDescription = if (isExpanded) L10n.Home.calendarExpanded else L10n.Home.calendarCollapsed }
                    .testTag("calendar.title"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.xSmall),
            ) {
                Text(selected.formatted("MMMy", locale), style = DsType.heading, color = Ds.primaryText.value)
                SfIcon("chevron.down", Modifier.rotate(turn), tint = Ds.primaryText.value, size = DsType.badge.fontSize)
            }
        },
        trailing = { TextAction(L10n.Home.today, Modifier.testTag("calendar.today"), color = Ds.primaryText.value) { selected = LocalDate.now() } },
        overlay = {
            PromptBar(L10n.Home.askPlaceholder, Modifier.align(Alignment.BottomCenter)) { router.open(AppRoute.Ask()) }
        },
    ) {
        Column(Modifier.fillMaxSize()) {
            DaysGrid(
                days, selected, visibleMonth, isExpanded, model::hasContent, { selected = it },
                Modifier.pointerInput(isExpanded) {
                    var total = 0f
                    detectHorizontalDragGestures(onDragStart = { total = 0f }, onDragEnd = {
                        // Sideways moves by what is on screen: a month when open, a week when closed.
                        if (kotlin.math.abs(total) > 30.dp.toPx()) {
                            val step = if (total < 0) 1L else -1L
                            selected = if (isExpanded) selected.plusMonths(step) else selected.plusWeeks(step)
                        }
                    }) { _, amount -> total += amount }
                },
            )
            AnimatedVisibility(isExpanded, enter = expandVertically(Motion.standard()) + fadeIn(Motion.standard()), exit = shrinkVertically(Motion.standard()) + fadeOut(Motion.standard())) {
                MonthStrip(CalendarGrid.months(LocalDate.now(), MONTHS_AROUND, MONTHS_AROUND), visibleMonth, ::choose)
            }
            HorizontalDivider(thickness = 0.5.dp, color = Ds.separator.value)
            // Meetings and recordings together, in the order the day went.
            val items = (model.events(selected).map { AgendaItem.Event(it) } + model.recordings(selected).map { AgendaItem.Meeting(it) }).sortedBy { it.start }
            if (items.isEmpty()) {
                EmptyDay(model) { scope.launch { model.connectCalendar(); model.loadCalendar(visibleMonth) } }
            } else {
                LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 96.dp)) {
                    itemsIndexed(items, key = { _, item -> item.key }) { index, item ->
                        Column {
                            when (item) {
                                is AgendaItem.Event -> EventRow(
                                    item.event, Modifier.padding(horizontal = Spacing.medium, vertical = 11.dp), showsDay = false,
                                    canRecord = item.event.end.isAfter(Instant.now()),
                                ) { onRecordEvent(item.event) }
                                is AgendaItem.Meeting -> {
                                    val enabled = item.recording.status == RecordingStatus.READY
                                    Box(
                                        Modifier.fillMaxWidth().alpha(if (enabled) 1f else 0.5f)
                                            .clickable(remember { MutableInteractionSource() }, indication = null, enabled = enabled) { router.push(AppRoute.Recording(item.recording.id)) }
                                            .padding(horizontal = Spacing.medium, vertical = 11.dp),
                                    ) { RecordingRow(item.recording, showsDay = false) }
                                }
                            }
                            if (index < items.lastIndex) RowDivider(Modifier.padding(start = Spacing.medium))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyDay(model: HomeModel, onConnect: () -> Unit) {
    when (model.calendarAccess) {
        CalendarAccess.GRANTED -> EmptyState(L10n.Home.dayEmpty, L10n.Home.noEventsMessage, "calendar")
        CalendarAccess.UNDETERMINED -> Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
            EmptyState(L10n.Home.dayEmpty, L10n.Home.connectMessage, "calendar", Modifier.heightIn(max = 220.dp), inline = true)
            PrimaryAction(L10n.Home.connect, Modifier.testTag("calendar.connect"), onClick = onConnect)
        }
        CalendarAccess.DENIED -> EmptyState(L10n.Home.dayEmpty, L10n.Home.calendarDenied, "calendar")
    }
}

/**
 * The weekday letters and the days under them. Custom because the platform's date picker has no week view, and it
 * could not share this animation. Each day is a real button, so TalkBack and font scaling work as usual.
 */
@Composable
private fun DaysGrid(
    days: List<LocalDate>,
    selected: LocalDate,
    month: LocalDate,
    isExpanded: Boolean,
    hasContent: (LocalDate) -> Boolean,
    onSelect: (LocalDate) -> Unit,
    modifier: Modifier = Modifier,
) {
    val locale = Strings.locale()
    val circle = with(LocalDensity.current) { (36.dp.toPx() * fontScale).toDp() }
    Column(modifier.fillMaxWidth().padding(Spacing.small), verticalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
        // Each day already says its full date, so TalkBack has no use for a row of letters.
        Row(Modifier.fillMaxWidth().clearAndSetSemantics {}) {
            for (letter in CalendarGrid.weekdayLetters(locale)) {
                Text(letter, style = DsType.note, color = Ds.secondaryText.value, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            }
        }
        for (week in days.chunked(CalendarGrid.DAYS_IN_WEEK)) {
            Row(Modifier.fillMaxWidth()) {
                for (date in week) {
                    val isSelected = date == selected
                    val inMonth = !isExpanded || (date.year == month.year && date.month == month.month)
                    val label = date.completeDate(locale)
                    Column(
                        Modifier.weight(1f).heightIn(min = 44.dp)
                            .clickable(remember { MutableInteractionSource() }, indication = null) { onSelect(date) }
                            .semantics(mergeDescendants = true) { role = Role.Button; contentDescription = label; this.selected = isSelected }
                            .testTag("calendar.day"),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        Box(Modifier.size(circle).clip(CircleShape).background(if (isSelected) Ds.primaryText.value else androidx.compose.ui.graphics.Color.Transparent), contentAlignment = Alignment.Center) {
                            Text(
                                date.formatted("d", locale), style = DsType.rowTitle,
                                color = when {
                                    isSelected -> Ds.background.value
                                    inMonth -> Ds.primaryText.value
                                    else -> Ds.secondaryText.value
                                },
                                modifier = Modifier.clearAndSetSemantics {},
                            )
                        }
                        Box(Modifier.size(4.dp).clip(CircleShape).background(if (hasContent(date)) Ds.action.value else androidx.compose.ui.graphics.Color.Transparent))
                    }
                }
            }
        }
    }
}

/** A row of months to jump between, with the year where it changes. */
@Composable
private fun MonthStrip(months: List<LocalDate>, selected: LocalDate, onSelect: (LocalDate) -> Unit) {
    val locale = Strings.locale()
    val scroll = rememberScrollState()
    val positions = remember { mutableMapOf<LocalDate, Int>() }
    var width by remember { mutableStateOf(0) }
    LaunchedEffect(selected, width) {
        val x = positions[selected] ?: return@LaunchedEffect
        scroll.animateScrollTo((x - width / 2).coerceAtLeast(0))
    }
    Row(
        Modifier.fillMaxWidth().onGloballyPositioned { width = it.size.width }.horizontalScroll(scroll)
            .padding(horizontal = Spacing.medium, vertical = Spacing.small),
        horizontalArrangement = Arrangement.spacedBy(Spacing.small),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        for (month in months) {
            if (month.monthValue == 1) Text(month.formatted("y", locale), style = DsType.heading, color = Ds.primaryText.value)
            val isSelected = month.year == selected.year && month.month == selected.month
            val label = month.formatted("MMMMy", locale)
            Box(
                Modifier
                    .onGloballyPositioned { positions[month] = (it.positionInParent().x + it.size.width / 2f).toInt() }
                    .heightIn(min = 44.dp)
                    .clip(CircleShape)
                    .background(if (isSelected) Ds.primaryText.value else Ds.surface.value)
                    .border(1.dp, Ds.selection.value, CircleShape)
                    .clickable(remember { MutableInteractionSource() }, indication = null) { onSelect(month) }
                    .semantics(mergeDescendants = true) { role = Role.Button; contentDescription = label; this.selected = isSelected }
                    .padding(horizontal = Spacing.medium)
                    .testTag("calendar.month"),
                contentAlignment = Alignment.Center,
            ) {
                Text(month.formatted("MMM", locale), style = DsType.meta, color = if (isSelected) Ds.background.value else Ds.primaryText.value, modifier = Modifier.clearAndSetSemantics {})
            }
        }
        Spacer(Modifier.size(0.dp))
    }
}

