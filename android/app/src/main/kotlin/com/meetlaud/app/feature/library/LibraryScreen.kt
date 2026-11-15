package com.meetlaud.app.feature.library

import com.meetlaud.app.feature.shared.NamePrompt
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.meetlaud.app.designsystem.AlertButton
import com.meetlaud.app.designsystem.Choice
import com.meetlaud.app.designsystem.ChoiceSheet
import com.meetlaud.app.designsystem.ContextMenuRow
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.FilledCheck
import com.meetlaud.app.designsystem.GlassCircleButton
import com.meetlaud.app.designsystem.IconSize
import com.meetlaud.app.designsystem.IosAlert
import com.meetlaud.app.designsystem.IosMenu
import com.meetlaud.app.designsystem.LocalDarkTheme
import com.meetlaud.app.designsystem.LocalReduceMotion
import com.meetlaud.app.designsystem.MenuAction
import com.meetlaud.app.designsystem.MenuDivider
import com.meetlaud.app.designsystem.Motion
import com.meetlaud.app.designsystem.PlainButton
import com.meetlaud.app.designsystem.RowDivider
import com.meetlaud.app.designsystem.RowLabel
import com.meetlaud.app.designsystem.SfIcon
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.designsystem.SwipeAction
import com.meetlaud.app.designsystem.SwipeRow
import com.meetlaud.app.designsystem.TapTarget
import com.meetlaud.app.designsystem.glass
import com.meetlaud.app.feature.shared.RecordingRow
import com.meetlaud.app.feature.shared.TranscriptionCenter
import com.meetlaud.app.feature.shared.title
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.localization.itemCount
import com.meetlaud.app.routing.AppRoute
import com.meetlaud.app.routing.LocalRouter
import com.meetlaud.app.shell.Screen
import com.meetlaud.app.shell.contentPadding
import com.meetlaud.domain.Folder
import com.meetlaud.domain.FolderID
import com.meetlaud.domain.Recording
import com.meetlaud.domain.RecordingID
import com.meetlaud.domain.RecordingSort
import kotlinx.coroutines.launch

/** The Library, as LibraryView.swift: folders that open in place, and the recordings in each. */
@Composable
fun LibraryScreen(library: LibraryController, center: TranscriptionCenter?) {
    val router = LocalRouter.current
    val scope = rememberCoroutineScope()
    var isSelecting by remember { mutableStateOf(false) }
    val selection = remember { mutableStateListOf<RecordingID>() }
    val expanded = remember { mutableStateListOf<FolderID>() }
    var isMainExpanded by remember { mutableStateOf(true) }
    var isNamingFolder by remember { mutableStateOf(false) }
    var renamingFolder by remember { mutableStateOf<Folder?>(null) }
    var renamingRecording by remember { mutableStateOf<Recording?>(null) }
    var movingRecording by remember { mutableStateOf<Recording?>(null) }
    var name by remember { mutableStateOf("") }
    var sortRevision by remember { mutableStateOf(0) }

    fun endSelection() {
        isSelecting = false
        selection.clear()
    }

    fun move(ids: List<RecordingID>, folder: FolderID?) {
        scope.launch { runCatching { library.service.move(ids, folder) } }
        endSelection()
    }

    // Read here so that a new sort order redraws the list.
    val active = if (sortRevision >= 0) library.active else emptyList()

    Screen(
        title = L10n.Nav.library,
        modifier = Modifier.testTag("screen.library"),
        trailing = {
            if (isSelecting) {
                PlainButton({ endSelection() }, Modifier.testTag("library.done").height(TapTarget).glass(CircleShape, LocalDarkTheme.current).padding(horizontal = Spacing.medium)) {
                    Text(L10n.Common.done, style = DsType.heading, color = Ds.primaryText.value)
                }
            } else {
                Row(Modifier.glass(CircleShape, LocalDarkTheme.current).clip(CircleShape)) {
                    PlainButton({ router.push(AppRoute.Search) }, Modifier.testTag("library.search").size(TapTarget), label = L10n.Library.search) {
                        Spacer(Modifier.weight(1f)); SfIcon("magnifyingglass", size = IconSize.icon); Spacer(Modifier.weight(1f))
                    }
                    var more by remember { mutableStateOf(false) }
                    var sortOpen by remember { mutableStateOf(false) }
                    Box {
                        PlainButton({ more = true }, Modifier.testTag("library.more").size(TapTarget), label = L10n.Library.more) {
                            Spacer(Modifier.weight(1f)); SfIcon("ellipsis", size = IconSize.icon); Spacer(Modifier.weight(1f))
                        }
                        IosMenu(more, { more = false }, listOf(
                            MenuAction(L10n.Library.select, "checkmark.circle") { isSelecting = true },
                            MenuAction("${L10n.Library.sortBy} · ${library.sort.title}", "arrow.up.arrow.down") { sortOpen = true },
                            MenuDivider,
                            MenuAction(L10n.Library.trash, "trash") { router.push(AppRoute.Trash) },
                        ))
                        IosMenu(sortOpen, { sortOpen = false }, RecordingSort.entries.map { option ->
                            MenuAction(option.title, isChecked = option == library.sort) {
                                library.sort = option
                                sortRevision++
                            }
                        }, title = L10n.Library.sortBy)
                    }
                }
            }
        },
        overlay = {
            AnimatedVisibility(isSelecting, Modifier.align(Alignment.BottomCenter).navigationBarsPadding(), enter = fadeIn() + expandVertically(), exit = fadeOut() + shrinkVertically()) {
                SelectionBar(selection.toList(), library, onMove = { move(selection.toList(), it) }, onFinish = ::endSelection)
            }
        },
    ) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = contentPadding()) {
            if (isSelecting) {
                items(active, key = { it.id.toString() }) { recording ->
                    val isSelected = recording.id in selection
                    PlainButton(
                        { if (isSelected) selection.remove(recording.id) else selection.add(recording.id) },
                        Modifier.fillMaxWidth().padding(horizontal = Spacing.medium, vertical = 11.dp),
                    ) {
                        if (isSelected) FilledCheck(Ds.action.value, 24.dp) else SfIcon("circle", 24.dp, tint = Ds.secondaryText.value)
                        Spacer(Modifier.width(Spacing.medium))
                        RecordingRow(recording, progress = center?.progress?.get(recording.id))
                    }
                    RowDivider(Modifier.padding(start = 56.dp, end = Spacing.medium))
                }
            } else {
                // Grouped once per update, as the iOS screen does.
                val groups = active.groupBy { it.folderID }
                item("header") {
                    Row(Modifier.fillMaxWidth().padding(start = Spacing.medium, end = Spacing.small, bottom = Spacing.xSmall), verticalAlignment = Alignment.CenterVertically) {
                        Text(L10n.Library.myFiles, style = DsType.pageTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f).semantics { heading() })
                        PlainButton({ name = ""; isNamingFolder = true }, Modifier.testTag("library.newFolder").size(TapTarget), label = L10n.Library.newFolder) {
                            Spacer(Modifier.weight(1f)); SfIcon("plus", tint = Ds.secondaryText.value, size = IconSize.icon); Spacer(Modifier.weight(1f))
                        }
                    }
                }
                item("main") {
                    FolderGroup(
                        L10n.Library.recordings, "mic", groups[null].orEmpty(), isMainExpanded, { isMainExpanded = !isMainExpanded },
                        emptyList(), library, center,
                        onRename = { name = it.title; renamingRecording = it },
                        onMoveSheet = { movingRecording = it },
                        onMove = { id, folder -> move(listOf(id), folder) },
                        tag = "library.folder.main",
                    )
                }
                items(library.folders, key = { it.id.toString() }) { folder ->
                    val isOpen = folder.id in expanded
                    FolderGroup(
                        folder.name, "folder", groups[folder.id].orEmpty(), isOpen, { if (isOpen) expanded.remove(folder.id) else expanded.add(folder.id) },
                        listOf(
                            SwipeAction(L10n.Ask.aboutFolder, "sparkles", Ds.action.value) { router.push(AppRoute.AskFolder(folder.id)) },
                            SwipeAction(L10n.Library.rename, "pencil", Ds.series[4].value) { name = folder.name; renamingFolder = folder },
                            SwipeAction(L10n.Library.delete, "trash", Ds.record.value) { scope.launch { runCatching { library.service.delete(folder) } } },
                        ).reversed(),
                        library, center,
                        onRename = { name = it.title; renamingRecording = it },
                        onMoveSheet = { movingRecording = it },
                        onMove = { id, target -> move(listOf(id), target) },
                        showsEmpty = true,
                        tag = "library.folder",
                    )
                }
            }
        }
    }

    if (isNamingFolder) {
        NamePrompt(L10n.Library.newFolder, name, { name = it }, onDismiss = { isNamingFolder = false }) {
            val folderName = name
            scope.launch { runCatching { library.service.createFolder(folderName) } }
        }
    }
    if (renamingFolder != null || renamingRecording != null) {
        NamePrompt(L10n.Library.rename, name, { name = it }, onDismiss = { renamingFolder = null; renamingRecording = null }) {
            val newName = name
            renamingFolder?.let { folder -> scope.launch { runCatching { library.service.rename(folder, newName) } } }
            renamingRecording?.let { recording -> scope.launch { runCatching { library.service.rename(recording.id, newName) } } }
        }
    }
    movingRecording?.let { recording ->
        MoveSheet(recording, library.folders, onMove = { move(listOf(recording.id), it) }, onDismiss = { movingRecording = null })
    }
}

/** A folder that opens in place, with its count, as a DisclosureGroup in the iOS list. */
@Composable
private fun FolderGroup(
    title: String,
    symbol: String,
    recordings: List<Recording>,
    isOpen: Boolean,
    onToggle: () -> Unit,
    swipe: List<SwipeAction>,
    library: LibraryController,
    center: TranscriptionCenter?,
    onRename: (Recording) -> Unit,
    onMoveSheet: (Recording) -> Unit,
    onMove: (RecordingID, FolderID?) -> Unit,
    showsEmpty: Boolean = false,
    tag: String,
) {
    val router = LocalRouter.current
    val scope = rememberCoroutineScope()
    val reduceMotion = LocalReduceMotion.current
    val turn by animateFloatAsState(if (isOpen) 90f else 0f, if (reduceMotion) Motion.reduced() else Motion.standard(), label = "chevron")
    Column {
        SwipeRow(trailing = swipe) {
            PlainButton(onToggle, Modifier.fillMaxWidth().testTag(tag).padding(horizontal = Spacing.medium, vertical = 11.dp)) {
                SfIcon(symbol, Modifier.width(Spacing.large), tint = Ds.secondaryText.value)
                Spacer(Modifier.width(Spacing.small))
                RowLabel(title, L10n.Library.itemCount(recordings.size), Modifier.weight(1f).padding(vertical = Spacing.xSmall))
                SfIcon("chevron.right", Modifier.rotate(turn), tint = Ds.action.value, size = DsType.meta.fontSize)
            }
        }
        RowDivider(Modifier.padding(horizontal = Spacing.medium))
        AnimatedVisibility(isOpen, enter = expandVertically(Motion.standard()) + fadeIn(), exit = shrinkVertically(Motion.standard()) + fadeOut()) {
            Column {
                for (recording in recordings) {
                    SwipeRow(
                        leading = listOf(SwipeAction(L10n.Library.move, "folder", Ds.action.value) { onMoveSheet(recording) }),
                        trailing = listOf(SwipeAction(L10n.Library.moveToTrash, "trash", Ds.record.value) {
                            scope.launch { runCatching { library.service.trash(listOf(recording.id)) } }
                        }),
                    ) {
                        var moveMenu by remember { mutableStateOf(false) }
                        Box {
                            ContextMenuRow(
                                listOf(
                                    MenuAction(L10n.Library.rename, "pencil") { onRename(recording) },
                                    MenuAction(L10n.Library.move, "folder") { moveMenu = true },
                                    MenuAction(L10n.Library.moveToTrash, "trash", isDestructive = true) {
                                        scope.launch { runCatching { library.service.trash(listOf(recording.id)) } }
                                    },
                                ),
                                onClick = { router.push(AppRoute.Recording(recording.id)) },
                            ) {
                                RecordingRow(recording, Modifier.padding(start = 56.dp, end = Spacing.medium, top = 11.dp, bottom = 11.dp), progress = center?.progress?.get(recording.id))
                            }
                            IosMenu(moveMenu, { moveMenu = false }, moveActions(library.folders) { onMove(recording.id, it) })
                        }
                    }
                    RowDivider(Modifier.padding(start = 56.dp, end = Spacing.medium))
                }
                if (showsEmpty && recordings.isEmpty()) {
                    Text(L10n.Library.folderEmpty, style = DsType.note, color = Ds.secondaryText.value, modifier = Modifier.padding(start = 56.dp, top = Spacing.compact, bottom = Spacing.compact))
                    RowDivider(Modifier.padding(start = 56.dp, end = Spacing.medium))
                }
            }
        }
    }
}

/** Every place a recording can go: the main list, then each folder. */
fun moveActions(folders: List<Folder>, onMove: (FolderID?) -> Unit): List<MenuAction> =
    listOf(MenuAction(L10n.Library.recordings) { onMove(null) }) + folders.map { folder -> MenuAction(folder.name) { onMove(folder.id) } }

/** Where one recording goes. The same list as everywhere else, with the current place marked. */
@Composable
fun MoveSheet(recording: Recording, folders: List<Folder>, onMove: (FolderID?) -> Unit, onDismiss: () -> Unit) {
    ChoiceSheet(
        L10n.Library.move, L10n.Common.close,
        listOf(Choice<FolderID?>(null, L10n.Library.recordings, "mic")) + folders.map { Choice<FolderID?>(it.id, it.name, "folder") },
        recording.folderID, onMove, onDismiss,
    )
}

/** Actions for the recordings selected in the Library: move, merge, and trash, on a glass bar. */
@Composable
private fun SelectionBar(ids: List<RecordingID>, library: LibraryController, onMove: (FolderID?) -> Unit, onFinish: () -> Unit) {
    val scope = rememberCoroutineScope()
    var moveOpen by remember { mutableStateOf(false) }
    Row(
        Modifier.padding(horizontal = Spacing.medium).padding(bottom = Spacing.small).fillMaxWidth()
            .glass(CircleShape, LocalDarkTheme.current).clip(CircleShape).padding(horizontal = Spacing.large, vertical = Spacing.xSmall),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Box {
            PlainButton({ moveOpen = true }, Modifier.size(TapTarget), enabled = ids.isNotEmpty(), label = L10n.Library.move) {
                Spacer(Modifier.weight(1f)); SfIcon("folder", size = IconSize.icon); Spacer(Modifier.weight(1f))
            }
            IosMenu(moveOpen, { moveOpen = false }, moveActions(library.folders, onMove))
        }
        PlainButton({ scope.launch { runCatching { library.service.merge(ids) } }; onFinish() }, Modifier.testTag("library.merge").size(TapTarget), enabled = ids.size >= 2, label = L10n.Library.merge) {
            Spacer(Modifier.weight(1f)); SfIcon("arrow.trianglehead.merge", size = IconSize.icon); Spacer(Modifier.weight(1f))
        }
        PlainButton({ scope.launch { runCatching { library.service.trash(ids) } }; onFinish() }, Modifier.testTag("library.trashSelected").size(TapTarget), enabled = ids.isNotEmpty(), label = L10n.Library.moveToTrash) {
            Spacer(Modifier.weight(1f)); SfIcon("trash", size = IconSize.icon, tint = if (ids.isEmpty()) Ds.secondaryText.value else Ds.record.value); Spacer(Modifier.weight(1f))
        }
    }
}

@Suppress("unused")
private val unusedButton: @Composable () -> Unit = { GlassCircleButton("plus", "") {} }
