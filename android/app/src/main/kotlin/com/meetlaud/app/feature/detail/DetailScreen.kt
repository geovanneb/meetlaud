package com.meetlaud.app.feature.detail

import com.meetlaud.app.feature.shared.languageName
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import com.meetlaud.app.designsystem.AlertButton
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.EmptyState
import com.meetlaud.app.designsystem.GlassCircleButton
import com.meetlaud.app.designsystem.IosActionSheet
import com.meetlaud.app.designsystem.IosAlert
import com.meetlaud.app.designsystem.IosMenu
import com.meetlaud.app.designsystem.MenuAction
import com.meetlaud.app.designsystem.PlayerBar
import com.meetlaud.app.designsystem.PlayerBarLabels
import com.meetlaud.app.designsystem.PrimaryAction
import com.meetlaud.app.designsystem.ProgressRing
import com.meetlaud.app.designsystem.PromptBar
import com.meetlaud.app.designsystem.SecondaryAction
import com.meetlaud.app.designsystem.ControlSize
import com.meetlaud.app.designsystem.SegmentedControl
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.designsystem.abbreviatedDateTime
import com.meetlaud.app.designsystem.clock
import com.meetlaud.app.feature.shared.NamePrompt
import com.meetlaud.app.feature.shared.LocalPreferences
import com.meetlaud.app.feature.shared.TranscribeOutcome
import com.meetlaud.app.feature.shared.TranscriptionStatusCard
import com.meetlaud.app.feature.shared.detail
import com.meetlaud.app.feature.shared.rememberPreference
import com.meetlaud.app.feature.shared.title
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.localization.Strings
import com.meetlaud.app.routing.AppRoute
import com.meetlaud.app.routing.LocalRouter
import com.meetlaud.app.shell.Screen
import com.meetlaud.domain.AskPreferences
import com.meetlaud.domain.Recording
import com.meetlaud.domain.TranscribePlan
import com.meetlaud.domain.TranscriptVersion
import kotlinx.coroutines.launch
import java.util.Locale

private enum class Tab { SUMMARY, TRANSCRIPT, NOTES }

private class PendingStart(val language: String?, val plan: TranscribePlan)

/** One meeting: its summary, transcript, and moments, with the player under them, as DetailView.swift. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun DetailScreen(model: DetailModel) {
    val router = LocalRouter.current
    val scope = rememberCoroutineScope()
    var tab by remember { mutableStateOf(Tab.TRANSCRIPT) }
    var isRenaming by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var isFindingAndReplacing by remember { mutableStateOf(false) }
    var isExporting by remember { mutableStateOf(false) }
    var isFollowing by remember { mutableStateOf(true) }
    var versions by remember { mutableStateOf<List<TranscriptVersion>>(emptyList()) }
    var restoring by remember { mutableStateOf<TranscriptVersion?>(null) }
    var pendingStart by remember { mutableStateOf<PendingStart?>(null) }
    var showsPolished by rememberPreference("transcript.polished", false)
    val list = rememberLazyListState()

    LaunchedEffect(model.id) {
        model.load()
        versions = model.versions()
        if (model.opensOnSummary) tab = Tab.SUMMARY
    }
    LaunchedEffect(model.id) { model.trackPlayback() }
    DisposableEffect(model.id) { onDispose { model.close() } }
    LaunchedEffect(model.progress) {
        model.refreshTranscript()
        versions = model.versions()
    }
    LaunchedEffect(model.summarySteps) { model.refreshSummaries() }
    // Only scrolling by the person stops following. Automatic scrolling must not count.
    LaunchedEffect(list) {
        list.interactionSource.interactions.collect { if (it is DragInteraction.Start) isFollowing = false }
    }

    fun begin(language: String?, whenCharging: Boolean) {
        scope.launch { if (model.transcribe(language, whenCharging) == TranscribeOutcome.NEEDS_MODEL) router.push(AppRoute.ModelSettings) }
    }

    /** A long job, or a device that is not at its best, gets a word before it starts. */
    fun start(language: String?) {
        scope.launch {
            val plan = model.transcribePlan(language)
            if (plan != null && plan.deservesNote) pendingStart = PendingStart(language, plan) else begin(language, false)
        }
    }

    Screen(
        modifier = Modifier.testTag("screen.detail"),
        trailing = {
            var more by remember { mutableStateOf(false) }
            var retranscribe by remember { mutableStateOf(false) }
            var earlier by remember { mutableStateOf(false) }
            Box {
                GlassCircleButton("ellipsis", L10n.Library.more, Modifier.testTag("detail.more")) { more = true }
                val actions = mutableListOf(MenuAction(L10n.Library.rename, "pencil") { name = model.recording?.title ?: ""; isRenaming = true })
                if (model.segments.isNotEmpty()) {
                    actions += MenuAction(L10n.Transcript.polish, "wand.and.stars", isChecked = showsPolished, tag = "detail.polish") { showsPolished = !showsPolished }
                    actions += MenuAction(L10n.Transcript.findReplace, "text.magnifyingglass") { isFindingAndReplacing = true }
                    actions += MenuAction(L10n.Transcript.retranscribe, "arrow.clockwise") { retranscribe = true }
                    if (versions.isNotEmpty()) actions += MenuAction(L10n.Transcript.earlier, "clock.arrow.circlepath", tag = "detail.versions") { earlier = true }
                }
                actions += MenuAction(L10n.Detail.export, "square.and.arrow.up", tag = "detail.export") { isExporting = true }
                actions += MenuAction(L10n.Library.moveToTrash, "trash", isDestructive = true) {
                    scope.launch {
                        model.moveToTrash()
                        router.pop()
                    }
                }
                IosMenu(more, { more = false }, actions)
                IosMenu(retranscribe, { retranscribe = false }, languageActions(::start))
                IosMenu(earlier, { earlier = false }, versions.map { version -> MenuAction(version.savedAt.abbreviatedDateTime()) { restoring = version } })
            }
        },
    ) {
        val recording = model.recording
        when {
            model.failed -> EmptyState(L10n.Detail.unavailableTitle, L10n.Detail.unavailableMessage, "exclamationmark.triangle")
            recording == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { ProgressRing(null) }
            else -> Column(Modifier.fillMaxSize().navigationBarsPadding()) {
                Box(Modifier.weight(1f)) {
                    LazyColumn(Modifier.fillMaxSize(), state = list) {
                        item("header") { Header(recording) }
                        stickyHeader("tabs") {
                            SegmentedControl(
                                listOf(L10n.Summary.title, L10n.Transcript.title, L10n.Detail.moments), tab.ordinal, { tab = Tab.entries[it] },
                                Modifier.background(Ds.background.value).padding(horizontal = Spacing.medium, vertical = Spacing.small).testTag("detail.tabs"),
                                tags = listOf("tab.summary", "tab.transcript", "tab.moments"),
                            )
                        }
                        when (tab) {
                            Tab.SUMMARY -> item("summary") { SummaryTab(model) { tab = Tab.TRANSCRIPT } }
                            Tab.NOTES -> item("moments") { MomentsTab(model) }
                            Tab.TRANSCRIPT -> transcriptTab(model, list, showsPolished, onStart = ::start, onFollow = { isFollowing = true })
                        }
                    }
                    val showsBack = tab == Tab.TRANSCRIPT && !isFollowing && model.isPlaying
                    androidx.compose.animation.AnimatedVisibility(showsBack, Modifier.align(Alignment.BottomEnd), enter = fadeIn() + slideInVertically { it / 3 }, exit = fadeOut()) {
                        SecondaryAction(L10n.Transcript.backToCurrent, Modifier.padding(Spacing.medium).testTag("transcript.backToCurrent"), ControlSize.REGULAR) {
                            isFollowing = true
                            scope.launch { scrollToActive(model, list, animated = true) }
                        }
                    }
                }
                if (model.segments.isNotEmpty()) AskBar(model)
                if (model.hasAudio) {
                    PlayerBar(
                        model.time, model.duration, model.isPlaying, model.markers.map { it.time }, model.rate,
                        PlayerBarLabels(L10n.Detail.play, L10n.Recorder.pause, L10n.Detail.back, L10n.Detail.forward, L10n.Detail.position, L10n.Detail.speed),
                        onSeek = model::seek, onToggle = model::togglePlayback, onRate = model::changeRate,
                    )
                }
            }
        }
    }

    // The active phrase stays in view while it plays, unless the person scrolled away.
    LaunchedEffect(model.activeSegmentID) {
        if (isFollowing && model.isPlaying && tab == Tab.TRANSCRIPT) scrollToActive(model, list, animated = true)
    }

    if (isRenaming) {
        NamePrompt(L10n.Library.rename, name, { name = it }, onDismiss = { isRenaming = false }) {
            val title = name
            scope.launch { model.rename(title) }
        }
    }
    restoring?.let { version ->
        IosAlert(
            L10n.Transcript.restoreTitle, L10n.Transcript.restoreMessage,
            listOf(
                AlertButton(L10n.Common.cancel, AlertButton.Role.CANCEL),
                AlertButton(L10n.Transcript.restore) { scope.launch { model.restore(version); versions = model.versions() } },
            ),
            onDismiss = { restoring = null },
        )
    }
    pendingStart?.let { pending ->
        val actions = mutableListOf(AlertButton(L10n.Transcript.startNow, tag = "transcript.startNow") { begin(pending.language, false) })
        if (pending.plan.canWaitForCharger) actions += AlertButton(L10n.Transcript.startWhenCharging, tag = "transcript.startWhenCharging") { begin(pending.language, true) }
        actions += AlertButton(L10n.Common.cancel, AlertButton.Role.CANCEL)
        IosActionSheet(L10n.Transcript.planTitle, pending.plan.message, actions, onDismiss = { pendingStart = null })
    }
    if (isFindingAndReplacing) FindReplaceSheet(model) { isFindingAndReplacing = false }
    if (isExporting) ExportSheet(model) { isExporting = false }
}

/** The transcript's rows: the work in progress first, then each phrase, or the invitation to transcribe. */
private fun androidx.compose.foundation.lazy.LazyListScope.transcriptTab(
    model: DetailModel,
    list: LazyListState,
    showsPolished: Boolean,
    onStart: (String?) -> Unit,
    onFollow: () -> Unit,
) {
    model.transcriptionProgress?.let { progress ->
        item("status") {
            val scope = rememberCoroutineScope()
            TranscriptionStatusCard(progress, Modifier.padding(Spacing.medium)) { scope.launch { model.cancelTranscription() } }
        }
    }
    if (model.segments.isEmpty() && model.progress == null) {
        item("empty") {
            var open by remember { mutableStateOf(false) }
            Column(Modifier.fillMaxWidth().heightIn(min = 420.dp).padding(Spacing.large), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.medium, Alignment.CenterVertically)) {
                Text(L10n.Transcript.emptyMessage, style = DsType.rowTitle, color = Ds.secondaryText.value, textAlign = TextAlign.Center)
                Box {
                    PrimaryAction(L10n.Transcript.transcribe, Modifier.testTag("transcript.start")) { open = true }
                    IosMenu(open, { open = false }, languageActions(onStart))
                }
            }
        }
    } else {
        itemsIndexed(model.segments, key = { _, segment -> segment.id.toString() }) { index, segment ->
            TranscriptRow(model, segment, index, showsPolished, onFollow)
        }
    }
}

private suspend fun scrollToActive(model: DetailModel, list: LazyListState, animated: Boolean) {
    val id = model.activeSegmentID ?: return
    val index = list.layoutInfo.totalItemsCount.let { _ ->
        val offset = 2 + (if (model.transcriptionProgress != null) 1 else 0)
        model.segments.indexOfFirst { it.id == id }.takeIf { it >= 0 }?.plus(offset)
    } ?: return
    // Centered, as scrollTo(anchor: .center).
    val viewport = list.layoutInfo.viewportSize.height
    if (animated) {
        list.animateScrollToItem(index, -viewport / 3)
    } else {
        list.scrollToItem(index, -viewport / 3)
    }
}

@Composable
private fun Header(recording: Recording) {
    Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.medium).padding(bottom = Spacing.small), verticalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
        Text(recording.title, style = DsType.pageTitle, color = Ds.primaryText.value, modifier = Modifier.semantics { heading() })
        val parts = mutableListOf(recording.createdAt.abbreviatedDateTime(), recording.duration.clock)
        if (recording.wasRecovered) parts += L10n.Recorder.recovered
        if (recording.attendees.isNotEmpty()) parts += recording.attendees.joinToString(", ")
        Text(parts.joinToString(" · "), style = DsType.meta, color = Ds.secondaryText.value)
    }
}

@Composable
private fun AskBar(model: DetailModel) {
    val router = LocalRouter.current
    val promptBar by rememberPreference(AskPreferences.PROMPT_BAR_KEY, AskPreferences.PromptBar.FOCUS.raw)
    PromptBar(L10n.Ask.aboutMeeting, Modifier.testTag("detail.ask")) {
        if (promptBar == AskPreferences.PromptBar.NEW_CHAT.raw) router.open(AppRoute.Ask(null)) else router.push(AppRoute.Ask(model.id))
    }
}

/** Detect, then the four languages, each named in the interface's language. */
fun languageActions(onPick: (String?) -> Unit): List<MenuAction> =
    listOf(MenuAction(L10n.Transcript.detectLanguage) { onPick(null) }) +
        listOf("en", "ja", "pt", "es").map { code -> MenuAction(languageName(code)) { onPick(code) } }

val TranscribePlan.message: String
    get() {
        val lines = mutableListOf<String>()
        val minutes = minutes
        lines += when {
            minutes == null -> L10n.Transcript.planUnknownTime
            minutes.first == minutes.last -> L10n.Transcript.planMinutes(minutes.last)
            else -> L10n.Transcript.planMinutesRange(minutes.first, minutes.last)
        }
        lines += rightNow.title
        rightNow.detail?.let { lines += it }
        return lines.joinToString("\n")
    }

@Suppress("unused")
private val unusedPreferences = LocalPreferences
