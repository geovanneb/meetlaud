package com.meetlaud.app.feature.home

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.GlassCapsule
import com.meetlaud.app.designsystem.IconSize
import com.meetlaud.app.designsystem.IosMenu
import com.meetlaud.app.designsystem.MenuAction
import com.meetlaud.app.designsystem.PlainButton
import com.meetlaud.app.designsystem.RecordSymbol
import com.meetlaud.app.designsystem.RowDivider
import com.meetlaud.app.designsystem.RowLabel
import com.meetlaud.app.designsystem.SfIcon
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.designsystem.TapTarget
import com.meetlaud.app.designsystem.dsCard
import com.meetlaud.app.designsystem.relativeSchedule
import com.meetlaud.app.designsystem.shortTime
import com.meetlaud.app.feature.shared.RECORDING_SORT_KEY
import com.meetlaud.app.feature.shared.RecordingRow
import com.meetlaud.app.feature.shared.TranscriptionCenter
import com.meetlaud.app.feature.shared.rememberPreference
import com.meetlaud.app.feature.shared.title
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.routing.AppRoute
import com.meetlaud.app.routing.LocalRouter
import com.meetlaud.app.shell.Screen
import com.meetlaud.app.shell.contentPadding
import com.meetlaud.domain.CalendarAccess
import com.meetlaud.domain.CalendarEvent
import com.meetlaud.domain.RecordingSort
import com.meetlaud.domain.RecordingStatus
import kotlinx.coroutines.launch

/** Home, as HomeView.swift: Upcoming, then Meeting notes, with Record and Add in the bar. */
@Composable
fun HomeScreen(
    model: HomeModel,
    center: TranscriptionCenter,
    onRecord: () -> Unit,
    onRecordEvent: (CalendarEvent) -> Unit,
    onImport: () -> Unit,
) {
    val router = LocalRouter.current
    val scope = rememberCoroutineScope()
    var sortRaw by rememberPreference(RECORDING_SORT_KEY, RecordingSort.NEWEST.raw)
    val sort = RecordingSort.from(sortRaw) ?: RecordingSort.NEWEST
    LaunchedEffect(Unit) { model.refreshEvents() }

    Screen(
        modifier = Modifier.testTag("screen.home"),
        trailing = {
            var addOpen by remember { mutableStateOf(false) }
            GlassCapsule {
                PlainButton(onRecord, Modifier.testTag("home.record").padding(start = Spacing.compact, end = Spacing.small).height(TapTarget)) {
                    RecordSymbol()
                    Spacer(Modifier.width(Spacing.xSmall))
                    Text(L10n.Home.record, style = DsType.rowTitle, color = Ds.primaryText.value)
                }
                Box {
                    PlainButton({ addOpen = true }, Modifier.testTag("home.add").size(TapTarget), label = L10n.Home.add) {
                        Spacer(Modifier.weight(1f))
                        SfIcon("plus", size = IconSize.iconLarge)
                        Spacer(Modifier.weight(1f))
                    }
                    IosMenu(
                        addOpen, { addOpen = false },
                        listOf(
                            MenuAction(L10n.Home.startRecording, "mic", onClick = onRecord),
                            MenuAction(L10n.Home.importFiles, "square.and.arrow.down", onClick = onImport),
                            MenuAction(L10n.Home.newChat, "plus.bubble") { router.open(AppRoute.Ask(null)) },
                        ),
                    )
                }
            }
        },
    ) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = contentPadding(top = 34.dp)) {
            item("upcoming.header") {
                SectionTitleRow(L10n.Home.upcoming, bottom = 2.dp) {
                    PlainButton({ router.push(AppRoute.Calendar) }, Modifier.testTag("home.calendar").height(TapTarget)) {
                        Text(L10n.Home.calendarView, style = DsType.meta, color = Ds.secondaryText.value)
                        Spacer(Modifier.width(Spacing.xSmall))
                        SfIcon("chevron.right", tint = Ds.secondaryText.value, size = DsType.meta.fontSize)
                    }
                }
            }
            item("upcoming") {
                Box(Modifier.animateContentSize()) {
                    when (model.calendarAccess) {
                        CalendarAccess.GRANTED ->
                            if (model.nextEvents.isEmpty()) {
                                Note(L10n.Home.noEvents)
                            } else {
                                Column {
                                    model.nextEvents.forEachIndexed { index, event ->
                                        if (index > 0) RowDivider(Modifier.padding(horizontal = Spacing.medium))
                                        EventRow(event, Modifier.padding(horizontal = Spacing.medium, vertical = 11.dp)) { onRecordEvent(event) }
                                    }
                                }
                            }
                        CalendarAccess.UNDETERMINED -> if (model.isConnectHidden) CalendarsOffCard { router.push(AppRoute.Calendars) } else ConnectCard(model) { scope.launch { model.connectCalendar() } }
                        CalendarAccess.DENIED -> Note(L10n.Home.calendarDenied)
                    }
                }
            }
            item("notes.header") {
                Spacer(Modifier.height(Spacing.compact))
                SectionTitleRow(L10n.Home.meetingNotes) {
                    var sortOpen by remember { mutableStateOf(false) }
                    Box {
                        PlainButton({ sortOpen = true }, Modifier.size(TapTarget), label = L10n.Library.sortBy) {
                            Spacer(Modifier.weight(1f))
                            SfIcon("arrow.up.arrow.down", tint = Ds.secondaryText.value, size = IconSize.icon)
                            Spacer(Modifier.weight(1f))
                        }
                        IosMenu(sortOpen, { sortOpen = false }, RecordingSort.entries.map { option ->
                            MenuAction(option.title, isChecked = option == sort) { sortRaw = option.raw }
                        }, title = L10n.Library.sortBy)
                    }
                }
            }
            if (model.recordings.isEmpty()) {
                item("empty") { EmptyNotes() }
            }
            val sorted = sort.sorted(model.recordings)
            items(sorted, key = { it.id.toString() }) { recording ->
                Column {
                    PlainButton(
                        { router.push(AppRoute.Recording(recording.id)) },
                        Modifier.fillMaxWidth().padding(horizontal = Spacing.medium, vertical = 13.5.dp),
                        enabled = recording.status == RecordingStatus.READY,
                    ) {
                        RecordingRow(recording, progress = center.progress[recording.id])
                    }
                    if (recording != sorted.last()) RowDivider(Modifier.padding(horizontal = Spacing.medium))
                }
            }
        }
    }
}

/** A section title with its action at the trailing edge, as Home's list headers. */
@Composable
private fun SectionTitleRow(title: String, bottom: androidx.compose.ui.unit.Dp = 10.dp, trailing: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(start = Spacing.medium, end = Spacing.small).padding(bottom = bottom), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = DsType.pageTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f).semantics { heading() })
        trailing()
    }
}

@Composable
private fun Note(text: String) {
    Text(text, style = DsType.meta, color = Ds.secondaryText.value, modifier = Modifier.padding(horizontal = Spacing.medium, vertical = Spacing.compact))
}

/** The card that offers the phone's calendars, with a button to close it. */
@Composable
private fun ConnectCard(model: HomeModel, onConnect: () -> Unit) {
    Row(Modifier.padding(horizontal = Spacing.medium, vertical = Spacing.small).dsCard(), verticalAlignment = Alignment.Top) {
        Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.medium)) {
            RowLabel(L10n.Home.connectTitle, L10n.Home.connectMessage, Modifier.weight(1f))
            PlainButton(onConnect, Modifier.testTag("home.connect").height(TapTarget)) {
                Text(L10n.Home.connect, style = DsType.rowTitle, color = Ds.action.value)
            }
        }
        Spacer(Modifier.width(Spacing.small))
        PlainButton({ model.hideConnect() }, Modifier.testTag("home.connect.hide").size(TapTarget), label = L10n.Home.hideConnect) {
            Spacer(Modifier.weight(1f))
            SfIcon("xmark", tint = Ds.secondaryText.value, size = DsType.meta.fontSize)
            Spacer(Modifier.weight(1f))
        }
    }
}

/** After the Connect card is closed: the same card, quieter, and the way back is in Settings. */
@Composable
private fun CalendarsOffCard(onOpen: () -> Unit) {
    PlainButton(onOpen, Modifier.testTag("home.calendarsOff").padding(horizontal = Spacing.medium, vertical = Spacing.small)) {
        Row(Modifier.dsCard(), verticalAlignment = Alignment.CenterVertically) {
            RowLabel(L10n.Home.calendarsOffTitle, L10n.Home.calendarsOffMessage, Modifier.weight(1f))
            Spacer(Modifier.width(Spacing.medium))
            SfIcon("chevron.right", tint = Ds.secondaryText.value)
        }
    }
}

@Composable
private fun EmptyNotes() {
    Column(Modifier.fillMaxWidth().padding(vertical = Spacing.large, horizontal = Spacing.medium), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.small)) {
        SfIcon("doc.text.magnifyingglass", Modifier.padding(bottom = Spacing.small), tint = Ds.secondaryText.value, size = IconSize.hero)
        Text(L10n.Home.emptyTitle, style = DsType.sectionTitle, color = Ds.primaryText.value, textAlign = TextAlign.Center, modifier = Modifier.testTag("home.empty").semantics { heading() })
        Text(L10n.Home.emptyMessage, style = DsType.meta, color = Ds.secondaryText.value, textAlign = TextAlign.Center)
    }
}

/** An event in Upcoming and in Calendar view, with a button that records it. */
@Composable
fun EventRow(event: CalendarEvent, modifier: Modifier = Modifier, showsDay: Boolean = true, canRecord: Boolean = true, onRecord: () -> Unit) {
    val whenText = if (showsDay) event.start.relativeSchedule() else event.start.shortTime()
    val detail = (listOf(whenText) + if (event.attendees.isEmpty()) emptyList() else listOf(event.attendees.take(3).joinToString(", "))).joinToString(" · ")
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        RowLabel(if (event.hasTitle) event.title else L10n.Home.untitledEvent, detail, Modifier.weight(1f))
        if (canRecord) {
            PlainButton(onRecord, Modifier.testTag("event.record").size(TapTarget), label = L10n.Home.record) {
                Spacer(Modifier.weight(1f))
                RecordSymbol(size = 26.dp)
                Spacer(Modifier.weight(1f))
            }
        }
    }
}
