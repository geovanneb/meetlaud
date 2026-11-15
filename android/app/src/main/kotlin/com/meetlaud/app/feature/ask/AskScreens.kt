package com.meetlaud.app.feature.ask

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.selection.SelectionContainer
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.meetlaud.app.designsystem.ActivityBar
import com.meetlaud.app.designsystem.ContextMenuRow
import com.meetlaud.app.designsystem.ControlSize
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.EmptyState
import com.meetlaud.app.designsystem.GlassCircleButton
import com.meetlaud.app.designsystem.IconSize
import com.meetlaud.app.designsystem.IosMenu
import com.meetlaud.app.designsystem.LocalDarkTheme
import com.meetlaud.app.designsystem.MenuAction
import com.meetlaud.app.designsystem.Motion
import com.meetlaud.app.designsystem.PlainButton
import com.meetlaud.app.designsystem.ProgressRing
import com.meetlaud.app.designsystem.PromptMetrics
import com.meetlaud.app.designsystem.Radius
import com.meetlaud.app.designsystem.RowDivider
import com.meetlaud.app.designsystem.RowLabel
import com.meetlaud.app.designsystem.SecondaryAction
import com.meetlaud.app.designsystem.SfIcon
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.designsystem.SwipeAction
import com.meetlaud.app.designsystem.SwipeRow
import com.meetlaud.app.designsystem.TapTarget
import com.meetlaud.app.designsystem.abbreviatedDateTime
import com.meetlaud.app.designsystem.clock
import com.meetlaud.app.designsystem.glass
import com.meetlaud.app.designsystem.promptPlacement
import com.meetlaud.app.feature.shared.NamePrompt
import com.meetlaud.app.feature.shared.displayName
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.routing.AppRoute
import com.meetlaud.app.routing.LocalRouter
import com.meetlaud.app.shell.LocalNavigationChrome
import com.meetlaud.app.shell.Screen
import com.meetlaud.domain.AnswerState
import com.meetlaud.domain.AskScope
import com.meetlaud.domain.ChatMessage
import com.meetlaud.domain.ChatRole
import com.meetlaud.domain.Citation
import com.meetlaud.domain.Conversation
import com.meetlaud.domain.IndexProgress
import com.meetlaud.domain.MemoryItem
import com.meetlaud.domain.Skill
import kotlinx.coroutines.launch

/** Every chat, and the way into a new one, as AskView.swift. */
@Composable
fun AskScreen(controller: AskController) {
    val scope = rememberCoroutineScope()
    var chat by remember { mutableStateOf<ChatModel?>(null) }
    var renaming by remember { mutableStateOf<Conversation?>(null) }
    var name by remember { mutableStateOf("") }
    val chrome = LocalNavigationChrome.current
    LaunchedEffect(Unit) { controller.reload() }
    LaunchedEffect(Unit) { controller.prepareSearch() }

    Screen(
        title = if (chat == null) L10n.Nav.ask else null,
        modifier = Modifier.testTag("screen.ask"),
        leading = {
            Row(Modifier.glass(CircleShape, LocalDarkTheme.current).clip(CircleShape)) {
                chrome.onMenu?.let { onMenu ->
                    PlainButton(onMenu, Modifier.size(TapTarget).testTag("drawer.toggle"), label = L10n.Nav.openMenu) {
                        Spacer(Modifier.weight(1f)); SfIcon("line.3.horizontal.decrease", size = 22.dp); Spacer(Modifier.weight(1f))
                    }
                }
                if (chat != null) {
                    PlainButton({ chat = null; scope.launch { controller.reload() } }, Modifier.size(TapTarget).testTag("ask.history"), label = L10n.Ask.history) {
                        Spacer(Modifier.weight(1f)); SfIcon("clock", size = 22.dp); Spacer(Modifier.weight(1f))
                    }
                }
            }
        },
        trailing = { GlassCircleButton("square.and.pencil", L10n.Ask.newChat, Modifier.testTag("ask.new")) { chat = controller.newChat(AskScope.Library) } },
    ) {
        AnimatedContent(chat, transitionSpec = { fadeIn(Motion.quick()) togetherWith fadeOut(Motion.quick()) }, contentKey = { it?.conversation?.id }, label = "ask") { current ->
            if (current != null) {
                ChatView(current, controller)
            } else {
                Box(Modifier.fillMaxSize()) {
                    LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(top = Spacing.medium, bottom = 96.dp)) {
                        if (controller.conversations.isEmpty() && controller.indexing == null) {
                            item("empty") { EmptyState(L10n.Ask.emptyTitle, L10n.Ask.emptyMessage, "sparkles", inline = true) }
                        }
                        controller.indexing?.let { progress -> item("indexing") { IndexingRow(progress, Modifier.padding(horizontal = Spacing.medium, vertical = Spacing.small)) } }
                        items(controller.conversations, key = { it.id.toString() }) { conversation ->
                            SwipeRow(trailing = listOf(
                                SwipeAction(L10n.Ask.delete, "trash", Ds.record.value) { scope.launch { controller.delete(conversation) } },
                                SwipeAction(L10n.Library.rename, "pencil", Ds.series[4].value) { name = conversation.title; renaming = conversation },
                            )) {
                                ContextMenuRow(
                                    listOf(
                                        MenuAction(L10n.Library.rename, "pencil") { name = conversation.title; renaming = conversation },
                                        MenuAction(L10n.Ask.delete, "trash", isDestructive = true) { scope.launch { controller.delete(conversation) } },
                                    ),
                                    onClick = { chat = controller.chat(conversation) },
                                    modifier = Modifier.testTag("ask.conversation"),
                                ) {
                                    RowLabel(conversation.title, conversation.updatedAt.abbreviatedDateTime(), Modifier.fillMaxWidth().padding(horizontal = Spacing.medium, vertical = 11.dp), titleLines = 2)
                                }
                            }
                            RowDivider(Modifier.padding(horizontal = Spacing.medium))
                        }
                    }
                    Box(Modifier.align(Alignment.BottomCenter).navigationBarsPadding().imePadding()) {
                        ChatComposer(L10n.Ask.placeholder, isBusy = false, onStop = {}) { question ->
                            val model = controller.newChat(AskScope.Library)
                            chat = model
                            model.send(question)
                        }
                    }
                }
            }
        }
    }
    renaming?.let { conversation ->
        NamePrompt(L10n.Library.rename, name, { name = it }, onDismiss = { renaming = null }) {
            val title = name
            scope.launch { controller.rename(conversation, title) }
        }
    }
}

@Composable
fun IndexingRow(progress: IndexProgress, modifier: Modifier = Modifier) {
    Column(modifier.semantics(mergeDescendants = true) {}.testTag("ask.indexing"), verticalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
        ActivityBar(progress.fraction)
        Text(L10n.Ask.indexing(progress.done, progress.total), style = DsType.note, color = Ds.secondaryText.value)
    }
}

/** Opens the chat about one meeting or folder, on top of wherever the person was, as ScopedChatView. */
@Composable
fun ScopedChatScreen(controller: AskController, scope: AskScope, skill: Skill? = null) {
    var chat by remember { mutableStateOf<ChatModel?>(null) }
    LaunchedEffect(scope, skill) {
        if (chat == null) {
            val model = if (skill == null) controller.chat(scope) else controller.newChat(scope)
            model.skill = skill
            chat = model
        }
    }
    LaunchedEffect(Unit) { controller.prepareSearch() }
    Screen {
        val current = chat
        if (current != null) ChatView(current, controller) else Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { ProgressRing(null) }
    }
}

@Composable
private fun ChatView(model: ChatModel, controller: AskController) {
    val router = LocalRouter.current
    val list = rememberLazyListState()
    var scopeTitle by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(model.conversation.id) {
        model.load()
        model.meeting?.let { scopeTitle = controller.title(it) }
    }
    LaunchedEffect(model.messages.size, model.partial) {
        if (list.layoutInfo.totalItemsCount > 0) list.animateScrollToItem(list.layoutInfo.totalItemsCount - 1)
    }
    val suggestions = listOf(L10n.Ask.suggestDecisions, L10n.Ask.suggestTasks, L10n.Ask.suggestRisks)
    Box(Modifier.fillMaxSize().testTag("ask.chat")) {
        LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = androidx.compose.foundation.layout.PaddingValues(Spacing.medium, Spacing.medium, Spacing.medium, 96.dp), verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
            item("scope") { ScopeMenu(model, controller, scopeTitle) }
            model.skill?.let { skill ->
                item("skill") {
                    Row(Modifier.testTag("ask.skill"), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
                        SfIcon("wand.and.stars", tint = Ds.secondaryText.value, size = DsType.meta.fontSize)
                        Text(L10n.Skills.active(skill.displayName), style = DsType.meta, color = Ds.secondaryText.value)
                    }
                }
            }
            if (!model.hasLanguageModel) {
                item("needsModel") {
                    Column(Modifier.testTag("ask.needsModel"), verticalArrangement = Arrangement.spacedBy(Spacing.small)) {
                        Text(L10n.Ask.needsModel, style = DsType.rowTitle, color = Ds.secondaryText.value)
                        SecondaryAction(L10n.Ask.getModel, size = ControlSize.REGULAR) { router.push(AppRoute.ModelSettings) }
                    }
                }
            }
            if (model.messages.isEmpty() && !model.isBusy) {
                item("suggestions") {
                    Column(verticalArrangement = Arrangement.spacedBy(Spacing.small)) {
                        for (suggestion in suggestions) {
                            SecondaryAction(suggestion, Modifier.testTag("ask.suggestion"), ControlSize.REGULAR, enabled = model.hasLanguageModel) { model.send(suggestion) }
                        }
                    }
                }
            }
            items(model.messages, key = { it.id.toString() }) { message ->
                MessageView(message) { router.push(AppRoute.Recording(it.recordingID, it.time)) }
            }
            if (model.isBusy) {
                item("activity") {
                    if (model.partial.isEmpty()) {
                        Row(Modifier.semantics(mergeDescendants = true) {}.testTag("ask.status"), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
                            ProgressRing(null)
                            Text(
                                when (model.status) {
                                    ChatModel.Status.WAITING -> L10n.Ask.statusWaiting
                                    ChatModel.Status.WRITING -> L10n.Ask.statusWriting
                                    else -> L10n.Ask.statusSearching
                                },
                                style = DsType.meta, color = Ds.secondaryText.value,
                            )
                        }
                    } else {
                        SelectionContainer { Text(model.partial, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.fillMaxWidth().testTag("ask.partial")) }
                    }
                }
            }
        }
        Box(Modifier.align(Alignment.BottomCenter).navigationBarsPadding().imePadding()) {
            ChatComposer(L10n.Ask.placeholder, model.isBusy, onStop = model::stop) { model.send(it) }
        }
    }
}

@Composable
private fun ScopeMenu(model: ChatModel, controller: AskController, scopeTitle: String?) {
    var open by remember { mutableStateOf(false) }
    val label = when (val scope = model.conversation.scope) {
        AskScope.Library -> L10n.Ask.scopeLibrary
        is AskScope.Folder -> controller.folders.firstOrNull { it.id == scope.id }?.name ?: L10n.Ask.scopeLibrary
        is AskScope.Recording -> scopeTitle ?: L10n.Ask.scopeMeeting
    }
    Box {
        PlainButton({ open = true }, Modifier.heightIn(min = TapTarget).semantics { contentDescription = L10n.Ask.scope; stateDescription = label }.testTag("ask.scope")) {
            Text(label, style = DsType.meta.copy(fontWeight = FontWeight.Bold), color = Ds.primaryText.value)
            Spacer(Modifier.width(Spacing.xSmall))
            SfIcon("chevron.down", size = DsType.badge.fontSize)
        }
        val actions = buildList {
            model.meeting?.let { meeting -> add(MenuAction(scopeTitle ?: L10n.Ask.scopeMeeting) { model.setScope(AskScope.Recording(meeting)) }) }
            add(MenuAction(L10n.Ask.scopeLibrary) { model.setScope(AskScope.Library) })
            controller.folders.forEach { folder -> add(MenuAction(folder.name) { model.setScope(AskScope.Folder(folder.id)) }) }
        }
        IosMenu(open, { open = false }, actions)
    }
}

@Composable
private fun MessageView(message: ChatMessage, onOpen: (Citation) -> Unit) {
    if (message.role == ChatRole.USER) {
        Row(Modifier.fillMaxWidth().testTag("ask.question")) {
            Spacer(Modifier.weight(1f).widthIn(Spacing.xLarge))
            SelectionContainer {
                Text(message.body, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.clip(RoundedCornerShape(Radius.medium)).background(Ds.selection.value).padding(Spacing.compact))
            }
        }
    } else {
        val text = when (message.state) {
            AnswerState.COMPLETE, AnswerState.STOPPED -> message.body
            AnswerState.NO_BASIS -> L10n.Ask.noBasis
            AnswerState.REMEMBERED -> L10n.Ask.remembered(message.body)
            AnswerState.FAILED -> L10n.Ask.failed
        }
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.small)) {
            if (text.isNotEmpty()) {
                SelectionContainer {
                    Text(text, style = DsType.rowTitle, color = if (message.state == AnswerState.COMPLETE) Ds.primaryText.value else Ds.secondaryText.value, modifier = Modifier.fillMaxWidth().testTag("ask.answer"))
                }
            }
            if (message.state == AnswerState.STOPPED) Text(L10n.Ask.stopped, style = DsType.note, color = Ds.secondaryText.value)
            for (citation in message.citations) {
                PlainButton({ onOpen(citation) }, Modifier.fillMaxWidth().testTag("ask.citation"), label = L10n.Ask.openSource(citation.recordingTitle, citation.time.clock)) {
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.medium)).background(Ds.surface.value).padding(Spacing.compact), horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
                        Text("${citation.number}", style = DsType.timestamp.copy(fontWeight = FontWeight.Bold), color = Ds.action.value)
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text("${citation.recordingTitle} · ${citation.time.clock}", style = DsType.note.copy(fontWeight = FontWeight.Bold), color = Ds.primaryText.value)
                            Text(citation.excerpt, style = DsType.note, color = Ds.secondaryText.value, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}

private fun Modifier.widthIn(min: androidx.compose.ui.unit.Dp): Modifier = this.then(Modifier.defaultMinSize(minWidth = min))

/**
 * Where a question is typed, as ChatComposer: the bar from Home, opened, with one round button that sends, and that
 * stops while an answer is being written, in the same place under the same finger.
 */
@Composable
fun ChatComposer(placeholder: String, isBusy: Boolean, onStop: () -> Unit, onSend: (String) -> Unit) {
    var text by remember { mutableStateOf("") }
    val focus = remember { FocusRequester() }
    val canSend = text.isNotBlank()
    val isActive = isBusy || canSend
    val fill by animateColorAsState(if (isActive) Ds.action.value else Ds.selection.value, Motion.quick(), label = "send")
    Row(
        Modifier
            .promptPlacement()
            .fillMaxWidth()
            .defaultMinSize(minHeight = PromptMetrics.minimumHeight)
            .glass(RoundedCornerShape(PromptMetrics.cornerRadius), LocalDarkTheme.current)
            .clip(RoundedCornerShape(PromptMetrics.cornerRadius))
            .clickable(remember { MutableInteractionSource() }, indication = null) { focus.requestFocus() }
            .padding(start = PromptMetrics.textInset, end = Spacing.xSmall, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        Box(Modifier.weight(1f).defaultMinSize(minHeight = TapTarget), contentAlignment = Alignment.CenterStart) {
            if (text.isEmpty()) Text(placeholder, style = DsType.rowTitle, color = Ds.secondaryText.value)
            BasicTextField(
                text, { text = it },
                Modifier.fillMaxWidth().focusRequester(focus).padding(vertical = Spacing.compact - 1.dp).testTag("ask.prompt"),
                textStyle = DsType.rowTitle.copy(color = Ds.primaryText.value),
                maxLines = 5,
                cursorBrush = SolidColor(Ds.action.value),
            )
        }
        PlainButton(
            {
                if (isBusy) {
                    onStop()
                } else {
                    val question = text
                    text = ""
                    onSend(question)
                }
            },
            Modifier.size(TapTarget).testTag(if (isBusy) "ask.stop" else "ask.send"),
            enabled = isActive,
            label = if (isBusy) L10n.Ask.stop else L10n.Ask.send,
        ) {
            Spacer(Modifier.weight(1f))
            Box(Modifier.size(36.dp).clip(CircleShape).background(fill), contentAlignment = Alignment.Center) {
                SfIcon(if (isBusy) "stop.fill" else "arrow.up", size = IconSize.row, tint = if (isActive) Ds.onAction.value else Ds.secondaryText.value)
            }
            Spacer(Modifier.weight(1f))
        }
    }
}

/** What the app keeps in mind in every chat, in plain sight, as MemoryView.swift. */
@Composable
fun MemoryScreen(controller: AskController) {
    val scope = rememberCoroutineScope()
    var isAdding by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<MemoryItem?>(null) }
    var text by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { controller.reload() }
    Screen(
        title = L10n.Ask.memory,
        modifier = Modifier.testTag("screen.memory"),
        trailing = { GlassCircleButton("plus", L10n.Ask.memoryAdd, Modifier.testTag("memory.add")) { text = ""; isAdding = true } },
    ) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = com.meetlaud.app.shell.contentPadding()) {
            if (controller.memories.isEmpty()) item("empty") { EmptyState(L10n.Ask.memory, L10n.Ask.memoryHint, "brain", inline = true) }
            items(controller.memories, key = { it.id.toString() }) { memory ->
                SwipeRow(trailing = listOf(SwipeAction(L10n.Ask.delete, "trash", Ds.record.value) { scope.launch { controller.delete(memory) } })) {
                    ContextMenuRow(
                        listOf(MenuAction(L10n.Ask.delete, "trash", isDestructive = true) { scope.launch { controller.delete(memory) } }),
                        onClick = { text = memory.text; editing = memory },
                        modifier = Modifier.testTag("memory.item"),
                    ) {
                        Text(memory.text, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.fillMaxWidth().heightIn(min = TapTarget).padding(horizontal = Spacing.medium, vertical = 11.dp))
                    }
                }
                RowDivider(Modifier.padding(horizontal = Spacing.medium))
            }
        }
    }
    if (isAdding) {
        NamePrompt(L10n.Ask.memoryAdd, text, { text = it }, onDismiss = { isAdding = false }) {
            val value = text
            scope.launch { controller.addMemory(value) }
        }
    }
    editing?.let { memory ->
        NamePrompt(L10n.Ask.memory, text, { text = it }, onDismiss = { editing = null }) {
            val value = text
            scope.launch { controller.update(memory, value) }
        }
    }
}
