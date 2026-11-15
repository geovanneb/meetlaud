package com.meetlaud.app.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.meetlaud.app.designsystem.AlertButton
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.EmptyState
import com.meetlaud.app.designsystem.IosActionSheet
import com.meetlaud.app.designsystem.LocalDarkTheme
import com.meetlaud.app.designsystem.MenuAction
import com.meetlaud.app.designsystem.ContextMenuRow
import com.meetlaud.app.designsystem.PlainButton
import com.meetlaud.app.designsystem.RowDivider
import com.meetlaud.app.designsystem.SearchField
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.designsystem.SwipeAction
import com.meetlaud.app.designsystem.SwipeRow
import com.meetlaud.app.designsystem.TapTarget
import com.meetlaud.app.designsystem.clock
import com.meetlaud.app.designsystem.glass
import com.meetlaud.app.feature.shared.RecordingRow
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.routing.AppRoute
import com.meetlaud.app.routing.LocalRouter
import com.meetlaud.app.shell.Screen
import com.meetlaud.app.shell.contentPadding
import com.meetlaud.domain.SearchHit
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Search, as SearchView.swift: titles, notes, and transcripts. The field sits at the bottom, where iOS 26 puts a
 * search field on a phone, and opens focused.
 */
@Composable
fun SearchScreen(library: LibraryController) {
    val router = LocalRouter.current
    var query by rememberSaveable { mutableStateOf("") }
    var hits by remember { mutableStateOf<List<SearchHit>>(emptyList()) }
    LaunchedEffect(query) {
        // Waits for a pause in typing, and is cancelled by the next keystroke.
        delay(150)
        hits = library.search(query)
    }
    Screen(
        title = L10n.Library.search,
        modifier = Modifier.testTag("screen.search"),
        overlay = {
            Box(Modifier.align(Alignment.BottomCenter).navigationBarsPadding().imePadding().padding(horizontal = Spacing.medium).padding(bottom = Spacing.small)) {
                SearchField(query, { query = it }, L10n.Library.search)
            }
        },
    ) {
        if (hits.isEmpty()) {
            EmptyState(if (query.isEmpty()) L10n.Library.search else L10n.Library.noResults, L10n.Library.searchHint, "magnifyingglass", Modifier.padding(bottom = 72.dp))
        } else {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = contentPadding().let { androidx.compose.foundation.layout.PaddingValues(top = it.calculateTopPadding(), bottom = 96.dp) }) {
                items(hits, key = { it.id.toString() }) { hit ->
                    PlainButton({ router.push(AppRoute.Recording(hit.recording.id, hit.time)) }, Modifier.fillMaxWidth().padding(horizontal = Spacing.medium, vertical = 11.dp)) {
                        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
                            RecordingRow(hit.recording)
                            hit.excerpt?.let { Text(listOf((hit.time ?: 0.0).clock, it).joinToString(" · "), style = DsType.meta, color = Ds.secondaryText.value) }
                        }
                    }
                    RowDivider(Modifier.padding(horizontal = Spacing.medium))
                }
            }
        }
    }
}

/** The trash, as TrashView.swift: swipe to restore or delete, and Empty Trash with a confirmation. */
@Composable
fun TrashScreen(library: LibraryController) {
    val scope = rememberCoroutineScope()
    var isConfirmingEmpty by remember { mutableStateOf(false) }
    val trashed = library.trashed
    Screen(
        title = L10n.Library.trash,
        modifier = Modifier.testTag("screen.trash"),
        trailing = {
            if (trashed.isNotEmpty()) {
                PlainButton({ isConfirmingEmpty = true }, Modifier.testTag("trash.empty").height(TapTarget).glass(CircleShape, LocalDarkTheme.current).padding(horizontal = Spacing.medium)) {
                    Text(L10n.Library.emptyTrash, style = DsType.rowTitle, color = Ds.primaryText.value)
                }
            }
        },
    ) {
        if (trashed.isEmpty()) {
            EmptyState(L10n.Library.trashEmptyTitle, L10n.Library.trashNotice, "trash")
        } else {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = contentPadding()) {
                items(trashed, key = { it.id.toString() }) { recording ->
                    SwipeRow(
                        leading = listOf(SwipeAction(L10n.Library.restore, "arrow.uturn.backward", Ds.action.value) { scope.launch { runCatching { library.service.restore(listOf(recording.id)) } } }),
                        trailing = listOf(SwipeAction(L10n.Library.delete, "trash", Ds.record.value) { scope.launch { runCatching { library.service.deleteForever(listOf(recording.id)) } } }),
                    ) {
                        ContextMenuRow(
                            listOf(MenuAction(L10n.Library.restore, "arrow.uturn.backward") { scope.launch { runCatching { library.service.restore(listOf(recording.id)) } } }),
                            onClick = {},
                        ) {
                            RecordingRow(recording, Modifier.padding(horizontal = Spacing.medium, vertical = 11.dp))
                        }
                    }
                    RowDivider(Modifier.padding(horizontal = Spacing.medium))
                }
                item("footer") {
                    Text(L10n.Library.trashNotice, style = DsType.note, color = Ds.secondaryText.value, modifier = Modifier.padding(horizontal = Spacing.medium, vertical = Spacing.small))
                }
            }
        }
    }
    if (isConfirmingEmpty) {
        IosActionSheet(
            L10n.Library.emptyTrashConfirm, null,
            listOf(
                AlertButton(L10n.Library.emptyTrash, AlertButton.Role.DESTRUCTIVE) { scope.launch { runCatching { library.service.emptyTrash() } } },
                AlertButton(L10n.Common.cancel, AlertButton.Role.CANCEL),
            ),
            onDismiss = { isConfirmingEmpty = false },
        )
    }
}
