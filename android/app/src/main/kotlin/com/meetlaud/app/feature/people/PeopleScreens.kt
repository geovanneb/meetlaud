package com.meetlaud.app.feature.people

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.EmptyState
import com.meetlaud.app.designsystem.GlassCircleButton
import com.meetlaud.app.designsystem.IosMenu
import com.meetlaud.app.designsystem.ListRow
import com.meetlaud.app.designsystem.ListSection
import com.meetlaud.app.designsystem.MenuAction
import com.meetlaud.app.designsystem.SwipeAction
import com.meetlaud.app.designsystem.SwipeRow
import com.meetlaud.app.feature.shared.NamePrompt
import com.meetlaud.app.feature.shared.RecordingRow
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.routing.AppRoute
import com.meetlaud.app.routing.LocalRouter
import com.meetlaud.app.shell.Screen
import com.meetlaud.app.shell.contentPadding
import com.meetlaud.domain.Person
import com.meetlaud.domain.Recording
import com.meetlaud.domain.RecordingStore
import com.meetlaud.domain.SpeakerService
import com.meetlaud.domain.SpeakerStore
import kotlinx.coroutines.launch
import java.util.UUID

/** Saved voices, as PeopleModel in PeopleView.swift. */
class PeopleModel(private val store: SpeakerStore, private val service: SpeakerService, private val recordings: RecordingStore) {
    var people by mutableStateOf<List<Person>>(emptyList())
        private set

    suspend fun meetings(person: Person): List<Recording> {
        val ids = runCatching { service.recordings(person) }.getOrDefault(emptyList())
        return ids.mapNotNull { id -> runCatching { recordings.recording(id) }.getOrNull()?.takeIf { it.deletedAt == null } }
            .sortedByDescending { it.createdAt }
    }

    suspend fun merge(source: Person, target: Person) {
        runCatching { service.merge(source, target) }
        refresh()
    }

    suspend fun refresh() {
        people = runCatching { store.people() }.getOrDefault(emptyList())
    }

    suspend fun rename(person: Person, name: String) {
        runCatching { service.rename(person, name) }
        refresh()
    }

    suspend fun delete(person: Person) {
        runCatching { service.delete(person) }
        refresh()
    }
}

/** Saved voices. These are biometric data, so deleting one must be easy and final. */
@Composable
fun PeopleScreen(model: PeopleModel) {
    val router = LocalRouter.current
    val scope = rememberCoroutineScope()
    var renaming by remember { mutableStateOf<Person?>(null) }
    var name by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { model.refresh() }
    Screen(title = L10n.People.title, modifier = Modifier.testTag("screen.people")) {
        if (model.people.isEmpty()) {
            EmptyState(L10n.People.emptyTitle, L10n.People.emptyMessage, "person.2")
        } else {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding())) {
                ListSection(footer = L10n.People.footer) {
                    model.people.forEachIndexed { index, person ->
                        SwipeRow(
                            trailing = listOf(
                                SwipeAction(L10n.Library.delete, "trash", Ds.record.value) { scope.launch { model.delete(person) } },
                                SwipeAction(L10n.Library.rename, "pencil", Ds.action.value) { name = person.name; renaming = person },
                            ),
                        ) {
                            ListRow(Modifier.testTag("people.row"), divider = index < model.people.lastIndex, onClick = { router.push(AppRoute.Person(person.id.toString())) }) {
                                Text(person.name, style = DsType.rowTitle, color = Ds.primaryText.value)
                            }
                        }
                    }
                }
            }
        }
    }
    renaming?.let { person ->
        NamePrompt(L10n.Library.rename, name, { name = it }, onDismiss = { renaming = null }) {
            val newName = name
            renaming = null
            scope.launch { model.rename(person, newName) }
        }
    }
}

/** One saved person: where they spoke, and how to fix a duplicate. */
@Composable
fun PersonScreen(id: String, model: PeopleModel) {
    val router = LocalRouter.current
    val scope = rememberCoroutineScope()
    val person = model.people.firstOrNull { it.id == UUID.fromString(id) }
    var meetings by remember { mutableStateOf<List<Recording>>(emptyList()) }
    var isMerging by remember { mutableStateOf(false) }
    LaunchedEffect(id) {
        if (model.people.isEmpty()) model.refresh()
        model.people.firstOrNull { it.id == UUID.fromString(id) }?.let { meetings = model.meetings(it) }
    }
    val others = model.people.filter { it.id != person?.id }
    Screen(
        title = person?.name ?: "",
        modifier = Modifier.testTag("screen.person"),
        trailing = {
            if (person != null && others.isNotEmpty()) {
                Box {
                    GlassCircleButton("ellipsis", L10n.People.mergeInto, Modifier.testTag("person.merge")) { isMerging = true }
                    IosMenu(isMerging, { isMerging = false }, others.map { other ->
                        MenuAction(other.name) {
                            scope.launch {
                                model.merge(person, other)
                                router.pop()
                            }
                        }
                    }, title = L10n.People.mergeInto)
                }
            }
        },
    ) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding())) {
            ListSection(L10n.People.meetings) {
                if (meetings.isEmpty()) {
                    ListRow(divider = false) { Text(L10n.People.noMeetings, style = DsType.meta, color = Ds.secondaryText.value) }
                }
                meetings.forEachIndexed { index, recording ->
                    ListRow(divider = index < meetings.lastIndex, onClick = { router.push(AppRoute.Recording(recording.id)) }) { RecordingRow(recording) }
                }
            }
        }
    }
}
