package com.meetlaud.app.feature.detail

import com.meetlaud.app.feature.shared.languageName
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.meetlaud.app.designsystem.ActivityBar
import com.meetlaud.app.designsystem.AlertButton
import com.meetlaud.app.designsystem.ContextMenuRow
import com.meetlaud.app.designsystem.ControlSize
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.EmptyState
import com.meetlaud.app.designsystem.FilledCheck
import com.meetlaud.app.designsystem.FormButton
import com.meetlaud.app.designsystem.FormRow
import com.meetlaud.app.designsystem.FormSection
import com.meetlaud.app.designsystem.FormTextField
import com.meetlaud.app.designsystem.FormToggle
import com.meetlaud.app.designsystem.IconSize
import com.meetlaud.app.designsystem.IosActionSheet
import com.meetlaud.app.designsystem.IosAlert
import com.meetlaud.app.designsystem.IosMenu
import com.meetlaud.app.designsystem.IosSheet
import com.meetlaud.app.designsystem.MenuAction
import com.meetlaud.app.designsystem.Motion
import com.meetlaud.app.designsystem.PlainButton
import com.meetlaud.app.designsystem.PrimaryAction
import com.meetlaud.app.designsystem.ProgressRing
import com.meetlaud.app.designsystem.Radius
import com.meetlaud.app.designsystem.SecondaryAction
import com.meetlaud.app.designsystem.SfIcon
import com.meetlaud.app.designsystem.SheetBar
import com.meetlaud.app.designsystem.SheetBody
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.designsystem.StatusBadge
import com.meetlaud.app.designsystem.TapTarget
import com.meetlaud.app.designsystem.TextAction
import com.meetlaud.app.designsystem.Tone
import com.meetlaud.app.designsystem.clock
import com.meetlaud.app.designsystem.dsCard
import com.meetlaud.app.feature.shared.Sharing
import com.meetlaud.app.feature.shared.TranscribeOutcome
import com.meetlaud.app.feature.shared.TranscriptionStatusCard
import com.meetlaud.app.feature.shared.percent
import com.meetlaud.app.feature.shared.rememberPreference
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.localization.sectionTitle
import com.meetlaud.app.localization.templateName
import com.meetlaud.app.routing.AppRoute
import com.meetlaud.app.routing.LocalRouter
import com.meetlaud.domain.MarkerKind
import com.meetlaud.domain.MindMapNode
import com.meetlaud.domain.SectionKind
import com.meetlaud.domain.Speaker
import com.meetlaud.domain.SpeakerCount
import com.meetlaud.domain.SpeakerStat
import com.meetlaud.domain.SpeakerStats
import com.meetlaud.domain.Summary
import com.meetlaud.domain.SummaryItem
import com.meetlaud.domain.SummaryParser
import com.meetlaud.domain.SummaryProgress
import com.meetlaud.domain.SummaryTemplate
import com.meetlaud.domain.TranscriptPolish
import com.meetlaud.domain.TranscriptSegment
import kotlinx.coroutines.launch

// MARK: - Summary

@Composable
fun SummaryTab(model: DetailModel, onOpenTranscript: () -> Unit) {
    val router = LocalRouter.current
    val scope = rememberCoroutineScope()
    var isChoosing by remember { mutableStateOf(false) }
    var isShowingMap by remember { mutableStateOf(false) }
    var isConfirmingDelete by remember { mutableStateOf(false) }
    var isConfirmingReminders by remember { mutableStateOf(false) }
    var reminderMessage by remember { mutableStateOf<String?>(null) }

    fun generate(template: SummaryTemplate, language: String?) {
        scope.launch { if (model.summarize(template, language) == TranscribeOutcome.NEEDS_MODEL) router.push(AppRoute.ModelSettings) }
    }

    Column {
        model.transcriptionProgress?.let { progress ->
            TranscriptionStatusCard(progress, Modifier.padding(Spacing.medium)) { scope.launch { model.cancelTranscription() } }
        }
        SpeakerShareSection(model)
        when {
            model.segments.isEmpty() && model.transcriptionProgress != null -> Unit
            model.segments.isEmpty() -> Prompt(L10n.Summary.needsTranscript) { PrimaryAction(L10n.Summary.openTranscript, onClick = onOpenTranscript) }
            model.summaries.isEmpty() -> Prompt(L10n.Summary.emptyMessage) {
                PrimaryAction(L10n.Summary.generate, Modifier.testTag("summary.generate")) { generate(model.defaultTemplate, null) }
                TextAction(L10n.Summary.choose, Modifier.testTag("summary.choose")) { isChoosing = true }
            }
            else -> Column {
                SummaryTabs(model, onAdd = { isChoosing = true }) { summary ->
                    var more by remember { mutableStateOf(false) }
                    Box {
                        PlainButton({ more = true }, Modifier.size(TapTarget).testTag("summary.more"), label = L10n.Library.more) {
                            Spacer(Modifier.weight(1f)); SfIcon("ellipsis", tint = Ds.action.value, size = IconSize.icon); Spacer(Modifier.weight(1f))
                        }
                        val context = LocalContext.current
                        val actions = mutableListOf(
                            MenuAction(L10n.Summary.mindMap, "point.3.connected.trianglepath.dotted", tag = "summary.mindMap") { isShowingMap = true },
                            MenuAction(L10n.Summary.share, "square.and.arrow.up") { Sharing.shareText(context, model.plainText(summary)) },
                        )
                        if (model.openTasks.isNotEmpty()) actions += MenuAction(L10n.Summary.toReminders, "checklist", tag = "summary.reminders") { isConfirmingReminders = true }
                        actions += MenuAction(L10n.Summary.regenerate, "arrow.clockwise") {
                            model.template(summary)?.let { generate(it, summary.language) } ?: run { isChoosing = true }
                        }
                        actions += MenuAction(L10n.Summary.delete, "trash", isDestructive = true) { isConfirmingDelete = true }
                        IosMenu(more, { more = false }, actions)
                    }
                }
                model.selectedSummary?.let { SummaryDocument(model, it) }
            }
        }
    }

    if (isChoosing) NewSummarySheet(model.templates, model.defaultTemplate, ::generate) { isChoosing = false }
    if (isShowingMap) model.selectedSummary?.let { summary ->
        MindMapSheet(model, MindMapNode.tree(model.recording?.title ?: "", summary)) { isShowingMap = false }
    }
    if (isConfirmingDelete) {
        IosAlert(
            L10n.Summary.deleteConfirm, null,
            listOf(AlertButton(L10n.Common.cancel, AlertButton.Role.CANCEL), AlertButton(L10n.Library.delete, AlertButton.Role.DESTRUCTIVE) { scope.launch { model.deleteSelectedSummary() } }),
            onDismiss = { isConfirmingDelete = false },
        )
    }
    if (isConfirmingReminders) {
        IosAlert(
            L10n.Summary.toReminders, L10n.Summary.toRemindersConfirm(model.openTasks.size),
            listOf(
                AlertButton(L10n.Common.cancel, AlertButton.Role.CANCEL),
                AlertButton(L10n.Summary.toReminders) {
                    scope.launch { reminderMessage = if (model.sendTasksToReminders()) L10n.Summary.remindersAdded else L10n.Summary.remindersDenied }
                },
            ),
            onDismiss = { isConfirmingReminders = false },
        )
    }
    reminderMessage?.let { message ->
        IosAlert(message, null, listOf(AlertButton(L10n.Common.ok)), onDismiss = { reminderMessage = null })
    }
}

@Composable
private fun Prompt(message: String, actions: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().heightIn(min = 380.dp).padding(Spacing.large),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.medium, Alignment.CenterVertically),
    ) {
        Text(message, style = DsType.rowTitle, color = Ds.secondaryText.value, textAlign = TextAlign.Center)
        actions()
    }
}

/** One capsule per summary, the chosen one filled, then Add and More. */
@Composable
private fun SummaryTabs(model: DetailModel, onAdd: () -> Unit, more: @Composable (Summary) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.medium).padding(bottom = Spacing.xSmall), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
        Row(Modifier.weight(1f).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
            for (summary in model.summaries) {
                val isSelected = summary.id == model.selectedSummaryID
                val fill by animateColorAsState(if (isSelected) Ds.selection.value else androidx.compose.ui.graphics.Color.Transparent, Motion.quick(), label = "tab")
                PlainButton({ model.selectedSummaryID = summary.id }, Modifier.height(TapTarget).semantics { selected = isSelected }.testTag("summary.tab")) {
                    // One weight in both states, so that the tabs around it keep their place.
                    Text(
                        L10n.Summary.templateName(summary.templateName), style = DsType.meta,
                        color = if (isSelected) Ds.primaryText.value else Ds.secondaryText.value,
                        modifier = Modifier.clip(CircleShape).background(fill).padding(horizontal = Spacing.compact, vertical = 9.dp),
                    )
                }
            }
        }
        PlainButton(onAdd, Modifier.size(TapTarget).testTag("summary.add"), label = L10n.Summary.add) {
            Spacer(Modifier.weight(1f)); SfIcon("plus", tint = Ds.action.value, size = IconSize.icon); Spacer(Modifier.weight(1f))
        }
        model.selectedSummary?.let { more(it) }
    }
}

/** A summary as a document: every claim shows where it came from, or that it needs checking. */
@Composable
private fun SummaryDocument(model: DetailModel, summary: Summary) {
    val progress = model.progress(summary)
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.medium).padding(bottom = Spacing.medium), verticalArrangement = Arrangement.spacedBy(Spacing.compact)) {
        progress?.let { StatusRow(it) { scope.launch { model.cancel(summary) } } }
        for (section in summary.sections) {
            Text(L10n.Summary.sectionTitle(section.title), style = DsType.heading, color = Ds.primaryText.value, modifier = Modifier.padding(top = Spacing.small).semantics { heading() })
            for (item in section.items) ItemRow(model, summary, item, section.kind)
            if (section.items.isEmpty()) Text(L10n.Summary.emptySection, style = DsType.rowTitle, color = Ds.secondaryText.value)
        }
        if (progress != null) {
            // Unfinished text can never be checked yet, so it stays quiet until the section is done.
            progress.partial?.let { text ->
                for (item in SummaryParser.items(text, SectionKind.BULLETS)) Text(item.text.replace("|", "·"), style = DsType.rowTitle, color = Ds.secondaryText.value)
            }
        } else if (!summary.isComplete) {
            Text(L10n.Summary.incomplete, style = DsType.rowTitle, color = Ds.secondaryText.value)
        }
        if (summary.isComplete) Text(L10n.Summary.aiNote, style = DsType.note, color = Ds.secondaryText.value, modifier = Modifier.padding(top = Spacing.small))
    }
}

@Composable
private fun StatusRow(progress: SummaryProgress, onCancel: () -> Unit) {
    val status = when (progress.phase) {
        SummaryProgress.Phase.QUEUED -> L10n.Summary.statusQueued
        SummaryProgress.Phase.READING -> L10n.Summary.statusReading
        SummaryProgress.Phase.WRITING -> L10n.Summary.statusWriting
        SummaryProgress.Phase.WAITING -> L10n.Summary.statusWaiting
    }
    Column(Modifier.dsCard(), verticalArrangement = Arrangement.spacedBy(Spacing.compact)) {
        when (progress.phase) {
            SummaryProgress.Phase.QUEUED, SummaryProgress.Phase.WAITING -> StatusBadge(
                status, if (progress.phase == SummaryProgress.Phase.WAITING) Tone.ATTENTION else Tone.WAITING, Modifier.testTag("summary.status"),
                symbol = if (progress.phase == SummaryProgress.Phase.WAITING) "pause.circle" else "hourglass",
            )
            else -> {
                ActivityBar(if (progress.fraction > 0) progress.fraction else null)
                Text(status, style = DsType.meta, color = Ds.secondaryText.value, modifier = Modifier.testTag("summary.status"))
            }
        }
        SecondaryAction(L10n.Common.cancel, size = ControlSize.REGULAR, onClick = onCancel)
    }
}

@Composable
private fun ItemRow(model: DetailModel, summary: Summary, item: SummaryItem, kind: SectionKind) {
    val scope = rememberCoroutineScope()
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
        if (kind == SectionKind.TASKS) {
            PlainButton(
                { scope.launch { model.toggle(item, summary) } },
                Modifier.size(TapTarget).semantics { selected = item.isDone }.testTag("summary.task"),
                label = if (item.isDone) L10n.Summary.markNotDone else L10n.Summary.markDone,
            ) {
                Spacer(Modifier.weight(1f))
                if (item.isDone) FilledCheck(Ds.action.value, 22.dp) else SfIcon("circle", 22.dp, tint = Ds.secondaryText.value)
                Spacer(Modifier.weight(1f))
            }
        }
        Column(Modifier.weight(1f).padding(top = if (kind == SectionKind.TASKS) 10.dp else 0.dp), verticalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
            Text(model.display(item.text), style = DsType.rowTitle.copy(textDecoration = if (item.isDone) TextDecoration.LineThrough else null), color = Ds.primaryText.value)
            model.detail(item)?.let { Text(it, style = DsType.meta, color = Ds.secondaryText.value) }
            if (item.needsReview) {
                Row(Modifier.semantics(mergeDescendants = true) {}.testTag("summary.review"), horizontalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
                    SfIcon("exclamationmark.triangle", tint = Ds.secondaryText.value, size = DsType.note.fontSize)
                    Text(L10n.Summary.checkThis, style = DsType.note, color = Ds.secondaryText.value)
                }
            }
        }
        item.sourceTime?.let { time ->
            PlainButton({ model.play(time) }, Modifier.height(TapTarget).testTag("summary.source"), enabled = model.hasAudio, label = L10n.Summary.listen(time.clock)) {
                Text(time.clock, style = DsType.timestamp, color = Ds.action.value)
            }
        }
    }
}

/**
 * Who spoke and how much, at the top of the summary (D-074). Closed, it is one line. Open, each person gets a row with
 * their share, time, and turns, and a row opens the same sheet as the transcript's name chips.
 */
@Composable
private fun SpeakerShareSection(model: DetailModel) {
    val scope = rememberCoroutineScope()
    var isExpanded by rememberPreference("summary.speakersExpanded", false)
    var selected by remember { mutableStateOf<Speaker?>(null) }
    var isChoosingCount by remember { mutableStateOf(false) }
    var hasSpeakerModel by remember { mutableStateOf(false) }
    LaunchedEffect(model.segments.size) { hasSpeakerModel = model.canSeparateSpeakers() }
    val stats = SpeakerStats.compute(model.speakers, model.segments)
    val canRedetect = hasSpeakerModel && model.transcript?.isComplete == true && model.segments.isNotEmpty() && model.progress == null
    val redetect = @Composable {
        SecondaryAction(L10n.Detail.speakersRedetect, Modifier.testTag("summary.speakersRedetect"), ControlSize.REGULAR, symbol = "arrow.triangle.2.circlepath") { isChoosingCount = true }
    }

    Box(Modifier.padding(horizontal = Spacing.medium).padding(bottom = Spacing.small)) {
        when {
            model.isRedetectingSpeakers -> Row(Modifier.dsCard().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.compact)) {
                ProgressRing(null)
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
                    Text(L10n.Transcript.stepSpeakers, style = DsType.heading, color = Ds.primaryText.value)
                    Text(L10n.Transcript.speakersNote, style = DsType.meta, color = Ds.secondaryText.value)
                }
            }
            stats.size > 1 -> Column(Modifier.dsCard().testTag("summary.speakers")) {
                val turn by animateFloatAsState(if (isExpanded) 90f else 0f, Motion.standard(), label = "chevron")
                PlainButton({ isExpanded = !isExpanded }, Modifier.fillMaxWidth()) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
                        Text(L10n.Detail.speakers, style = DsType.heading, color = Ds.primaryText.value)
                        Text(stats.mapNotNull { stat -> model.speakers.firstOrNull { it.id == stat.speakerID }?.let { "${model.name(it)} ${percent(stat.share)}" } }.joinToString(" · "), style = DsType.meta, color = Ds.secondaryText.value)
                    }
                    SfIcon("chevron.right", Modifier.rotate(turn), tint = Ds.secondaryText.value, size = DsType.meta.fontSize)
                }
                AnimatedVisibility(isExpanded, enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
                    Column(Modifier.padding(top = Spacing.small), verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
                        for (stat in stats) model.speakers.firstOrNull { it.id == stat.speakerID }?.let { StatRow(model, stat, it) { selected = it } }
                        if (canRedetect) redetect()
                    }
                }
            }
            canRedetect -> Column(Modifier.dsCard().testTag("summary.speakersOne"), verticalArrangement = Arrangement.spacedBy(Spacing.compact)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
                    SfIcon("person.wave.2", size = DsType.heading.fontSize)
                    Text(L10n.Detail.speakersOne, style = DsType.heading, color = Ds.primaryText.value)
                }
                Text(L10n.Detail.speakersWrong, style = DsType.meta, color = Ds.secondaryText.value)
                redetect()
            }
        }
    }
    selected?.let { speaker -> SpeakerSheet(speaker, model) { selected = null } }
    if (isChoosingCount) {
        IosActionSheet(
            L10n.Detail.speakersCountTitle, L10n.Detail.speakersRedetectNote,
            listOf(AlertButton(L10n.Detail.speakersCountAuto) { scope.launch { model.redetectSpeakers(SpeakerCount.Automatic) } }) +
                SpeakerCount.choices.map { count -> AlertButton(L10n.Detail.speakersCountPeople(count)) { scope.launch { model.redetectSpeakers(SpeakerCount.Exactly(count)) } } } +
                AlertButton(L10n.Common.cancel, AlertButton.Role.CANCEL),
            onDismiss = { isChoosingCount = false },
        )
    }
}

@Composable
private fun StatRow(model: DetailModel, stat: SpeakerStat, speaker: Speaker, onOpen: () -> Unit) {
    val share = percent(stat.share)
    val detail = L10n.Detail.speakerDetail(stat.talkTime.clock, stat.turns, stat.longestTurn.clock)
    PlainButton(onOpen, Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = "${model.name(speaker)}, $share. $detail" }) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(model.name(speaker), style = DsType.rowTitle, color = Ds.primaryText.value)
                if (speaker.isSuggested) {
                    Spacer(Modifier.width(Spacing.small))
                    Text(L10n.People.suggested, style = DsType.badge, color = Ds.secondaryText.value)
                }
                Spacer(Modifier.weight(1f))
                Text(share, style = DsType.rowTitle.copy(fontFeatureSettings = "tnum"), color = Ds.primaryText.value)
            }
            ActivityBar(stat.share)
            Text(detail, style = DsType.note, color = Ds.secondaryText.value)
        }
    }
}

// MARK: - Transcript

/** A phrase, with the speaker's name above when the voice changes, as a script does. */
@Composable
fun TranscriptRow(model: DetailModel, segment: TranscriptSegment, index: Int, showsPolished: Boolean, onFollow: () -> Unit) {
    val scope = rememberCoroutineScope()
    var editing by remember { mutableStateOf(false) }
    var edited by remember { mutableStateOf("") }
    var speakerMenu by remember { mutableStateOf(false) }
    var selectedSpeaker by remember { mutableStateOf<Speaker?>(null) }
    val isActive = model.activeSegmentID == segment.id
    val background by animateColorAsState(if (isActive) Ds.selection.value else androidx.compose.ui.graphics.Color.Transparent, Motion.quick(), label = "active")
    Column(Modifier.padding(horizontal = Spacing.medium).padding(bottom = Spacing.small)) {
        val speaker = model.speaker(segment)
        if (speaker != null && (index == 0 || model.segments[index - 1].speaker != segment.speaker)) {
            PlainButton({ selectedSpeaker = speaker }, Modifier.height(TapTarget).padding(horizontal = Spacing.small).testTag("speaker.chip"), label = model.name(speaker)) {
                Row(
                    Modifier.clip(CircleShape).background(Ds.selection.value).padding(horizontal = Spacing.compact, vertical = Spacing.xSmall + 2.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.xSmall),
                ) {
                    Text(model.name(speaker), style = DsType.meta.copy(fontWeight = FontWeight.Bold), color = Ds.primaryText.value)
                    when {
                        speaker.isSuggested -> Text(L10n.People.suggested, style = DsType.badge, color = Ds.action.value)
                        speaker.name == null -> Text(L10n.People.addName, style = DsType.badge, color = Ds.secondaryText.value)
                    }
                    SfIcon("pencil", tint = Ds.secondaryText.value, size = DsType.badge.fontSize)
                }
            }
        }
        Box {
            val actions = mutableListOf(MenuAction(L10n.Transcript.edit, "pencil") { edited = segment.text; editing = true })
            if (model.speakers.size > 1) actions += MenuAction(L10n.People.changeSpeaker, "person") { speakerMenu = true }
            ContextMenuRow(actions, onClick = { onFollow(); model.play(segment.start) }, Modifier.semantics { selected = isActive }.testTag("transcript.segment")) {
                Column(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.small)).background(background).padding(Spacing.small),
                    verticalArrangement = Arrangement.spacedBy(Spacing.xSmall),
                ) {
                    Text(segment.start.clock, style = DsType.timestamp, color = Ds.secondaryText.value)
                    Text(if (showsPolished) TranscriptPolish.polish(segment.text) else segment.text, style = DsType.rowTitle, color = Ds.primaryText.value)
                }
            }
            IosMenu(speakerMenu, { speakerMenu = false }, model.speakers.map { other -> MenuAction(model.name(other)) { scope.launch { model.setSpeaker(other, segment) } } })
        }
    }
    if (editing) {
        IosAlert(
            L10n.Transcript.edit, null,
            listOf(
                AlertButton(L10n.Common.cancel, AlertButton.Role.CANCEL),
                AlertButton(L10n.Common.save) { scope.launch { model.save(segment.copy(text = edited)) } },
            ),
            onDismiss = { editing = false },
            field = {
                androidx.compose.material3.OutlinedTextField(edited, { edited = it }, textStyle = DsType.rowTitle, shape = RoundedCornerShape(10.dp), modifier = Modifier.fillMaxWidth())
            },
        )
    }
    selectedSpeaker?.let { SpeakerSheet(it, model) { selectedSpeaker = null } }
}

// MARK: - Moments

/** The flags, notes, and photos of a recording. Each one plays its moment. */
@Composable
fun MomentsTab(model: DetailModel) {
    if (model.markers.isEmpty()) {
        EmptyState(L10n.Detail.moments, L10n.Detail.noMoments, "flag", Modifier.heightIn(min = 420.dp), inline = true)
        return
    }
    Column(Modifier.padding(horizontal = Spacing.medium, vertical = Spacing.small), verticalArrangement = Arrangement.spacedBy(Spacing.small)) {
        for (marker in model.markers) {
            PlainButton({ model.play(marker.time) }, Modifier.fillMaxWidth().heightIn(min = TapTarget).semantics(mergeDescendants = true) {}) {
                Text(marker.time.clock, style = DsType.timestamp, color = Ds.secondaryText.value)
                Spacer(Modifier.width(Spacing.small))
                val image = remember(marker.id) { model.image(marker) }
                if (image != null) {
                    Image(image.asImageBitmap(), null, Modifier.size(56.dp).clip(RoundedCornerShape(Radius.small)), contentScale = ContentScale.Crop)
                } else {
                    SfIcon(if (marker.kind == MarkerKind.NOTE) "square.and.pencil" else "flag.fill", tint = Ds.action.value)
                }
                Spacer(Modifier.width(Spacing.small))
                Text(marker.text ?: L10n.Detail.moment, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f))
            }
        }
    }
}

// MARK: - Sheets

/** Everything about one speaker in this recording, from a tap on their name, as SpeakerSheet.swift. */
@Composable
fun SpeakerSheet(speaker: Speaker, model: DetailModel, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf(speaker.name ?: "") }
    var people by remember { mutableStateOf(emptyList<com.meetlaud.domain.Person>()) }
    var remembersVoice by remember { mutableStateOf(false) }
    var isConfirmingVoice by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(speaker.id) { people = model.savedPeople() }
    val trimmed = name.trim()
    val others = model.speakers.filter { it.id != speaker.id }
    fun act(work: suspend () -> Unit) {
        scope.launch {
            work()
            onDismiss()
        }
    }

    IosSheet(onDismiss) {
        SheetBar(
            model.name(speaker),
            leading = { TextAction(L10n.Common.cancel, color = Ds.primaryText.value, onClick = onDismiss) },
            trailing = {
                // One way to finish: the name and the voice are saved together, for this speaker only.
                TextAction(L10n.Common.save, Modifier.testTag("speaker.save"), enabled = trimmed.isNotEmpty(), style = DsType.heading) {
                    if (remembersVoice) isConfirmingVoice = true else act { model.rename(speaker, name) }
                }
            },
        )
        SheetBody(Modifier.padding(top = Spacing.medium)) {
            if (speaker.isSuggested) {
                FormSection {
                    FormRow { Text(L10n.People.suggestion(speaker.name ?: ""), style = DsType.rowTitle, color = Ds.primaryText.value) }
                    FormButton(L10n.People.confirm, Modifier.testTag("speaker.confirm"), divider = false) { act { model.confirm(speaker) } }
                }
            }
            FormSection(L10n.People.nameSection) {
                FormTextField(name, { name = it }, L10n.Library.namePlaceholder, Modifier.testTag("speaker.name"), divider = false)
            }
            if (people.isNotEmpty()) {
                FormSection(L10n.People.pickSaved) {
                    people.forEachIndexed { index, person ->
                        FormRow(divider = index < people.lastIndex, onClick = { act { model.assign(speaker, person) } }) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                SfIcon("person.crop.circle", Modifier.width(Spacing.large), tint = Ds.action.value)
                                Spacer(Modifier.width(Spacing.compact))
                                Text(person.name, style = DsType.rowTitle, color = Ds.primaryText.value)
                            }
                        }
                    }
                }
            }
            FormSection(footer = L10n.People.saveVoiceNote) {
                FormToggle(
                    if (trimmed.isEmpty()) L10n.People.saveVoice else L10n.People.rememberVoice(trimmed), remembersVoice, { remembersVoice = it },
                    Modifier.testTag("speaker.saveVoice"), enabled = trimmed.isNotEmpty(), divider = error != null,
                )
                error?.let { FormRow(divider = false) { Text(it, style = DsType.rowTitle, color = Ds.record.value) } }
            }
            if (others.isNotEmpty()) {
                FormSection(L10n.People.mergeSection) {
                    others.forEachIndexed { index, other ->
                        FormButton(model.name(other), divider = index < others.lastIndex) { act { model.merge(speaker, other) } }
                    }
                }
            }
        }
    }
    if (isConfirmingVoice) {
        IosAlert(
            L10n.People.consentTitle, L10n.People.consentMessage(trimmed),
            listOf(
                AlertButton(L10n.Common.cancel, AlertButton.Role.CANCEL),
                AlertButton(L10n.People.consentAccept, tag = "speaker.consent") {
                    scope.launch {
                        when (model.saveVoice(speaker, name)) {
                            DetailModel.SaveVoiceResult.SAVED -> onDismiss()
                            DetailModel.SaveVoiceResult.TOO_LITTLE_SPEECH -> error = L10n.People.tooLittleSpeech
                            DetailModel.SaveVoiceResult.UNAVAILABLE -> error = L10n.People.saveFailed
                        }
                    }
                },
            ),
            onDismiss = { isConfirmingVoice = false },
        )
    }
}

@Composable
fun FindReplaceSheet(model: DetailModel, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var find by remember { mutableStateOf("") }
    var replacement by remember { mutableStateOf("") }
    var result by remember { mutableStateOf<Int?>(null) }
    IosSheet(onDismiss, large = false) {
        SheetBar(
            L10n.Transcript.findReplace,
            leading = { TextAction(L10n.Common.done, color = Ds.primaryText.value, onClick = onDismiss) },
            trailing = { TextAction(L10n.Transcript.replaceAll, enabled = find.isNotEmpty(), style = DsType.heading) { scope.launch { result = model.replaceAll(find, replacement) } } },
        )
        SheetBody(Modifier.padding(top = Spacing.medium)) {
            FormSection {
                FormTextField(find, { find = it }, L10n.Transcript.find)
                FormTextField(replacement, { replacement = it }, L10n.Transcript.replaceWith, divider = result != null)
                result?.let { FormRow(divider = false) { Text(L10n.Transcript.replaced(it), style = DsType.rowTitle, color = Ds.secondaryText.value) } }
            }
        }
    }
}

/** Picks what a new summary looks like: a language and a template. */
@Composable
fun NewSummarySheet(templates: List<SummaryTemplate>, initial: SummaryTemplate, onGenerate: (SummaryTemplate, String?) -> Unit, onDismiss: () -> Unit) {
    var selected by remember { mutableStateOf(initial) }
    var language by remember { mutableStateOf<String?>(null) }
    var languageMenu by remember { mutableStateOf(false) }
    IosSheet(onDismiss) {
        SheetBar(
            L10n.Summary.add,
            leading = { TextAction(L10n.Common.cancel, color = Ds.primaryText.value, onClick = onDismiss) },
            trailing = { TextAction(L10n.Summary.generateAction, Modifier.testTag("summary.sheet.generate"), style = DsType.heading) { onGenerate(selected, language); onDismiss() } },
        )
        SheetBody(Modifier.padding(top = Spacing.medium)) {
            FormSection {
                FormRow(divider = false, onClick = { languageMenu = true }) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(L10n.Summary.language, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f))
                        Box {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(language?.let(::languageName) ?: L10n.Summary.languageAuto, style = DsType.rowTitle, color = Ds.secondaryText.value)
                                SfIcon("chevron.up", tint = Ds.secondaryText.value, size = DsType.note.fontSize)
                            }
                            IosMenu(languageMenu, { languageMenu = false }, listOf(MenuAction(L10n.Summary.languageAuto, isChecked = language == null) { language = null }) +
                                listOf("en", "ja", "pt", "es").map { code -> MenuAction(languageName(code), isChecked = language == code) { language = code } })
                        }
                    }
                }
            }
            FormSection(L10n.Summary.template) {
                templates.forEachIndexed { index, template ->
                    FormRow(Modifier.semantics { this.selected = template.id == selected.id }, divider = index < templates.lastIndex, onClick = { selected = template }) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(L10n.Summary.templateName(template.name), style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f))
                            if (template.id == selected.id) SfIcon("checkmark", tint = Ds.action.value)
                        }
                    }
                }
            }
        }
    }
}

/** The summary as a branching outline, as MindMapView.swift. Each node is a plain button, read in order by TalkBack. */
@Composable
fun MindMapSheet(model: DetailModel, root: MindMapNode, onDismiss: () -> Unit) {
    val collapsed = remember { mutableStateListOf<String>() }
    IosSheet(onDismiss) {
        SheetBar(L10n.Summary.mindMap, leading = { TextAction(L10n.Common.done, color = Ds.primaryText.value, onClick = onDismiss) })
        SheetBody(Modifier.padding(Spacing.medium).testTag("screen.mindMap")) {
            Text(root.title, style = DsType.pageTitle, color = Ds.primaryText.value, modifier = Modifier.semantics { heading() })
            Spacer(Modifier.height(Spacing.compact))
            for (node in root.children) {
                val isOpen = node.id !in collapsed
                val turn by animateFloatAsState(if (isOpen) 90f else 0f, Motion.standard(), label = "branch")
                PlainButton(
                    { if (isOpen) collapsed.add(node.id) else collapsed.remove(node.id) },
                    Modifier.fillMaxWidth().heightIn(min = TapTarget).clip(RoundedCornerShape(Radius.medium)).background(Ds.surface.value).padding(horizontal = Spacing.compact).semantics { selected = isOpen }.testTag("mindmap.branch"),
                ) {
                    SfIcon("chevron.right", Modifier.rotate(turn), size = DsType.badge.fontSize)
                    Spacer(Modifier.width(Spacing.small))
                    Text(L10n.Summary.sectionTitle(node.title), style = DsType.heading, color = Ds.primaryText.value, modifier = Modifier.weight(1f))
                    Text("${node.children.size}", style = DsType.badge, color = Ds.secondaryText.value)
                }
                AnimatedVisibility(isOpen, enter = expandVertically() + fadeIn(), exit = shrinkVertically() + fadeOut()) {
                    Row(Modifier.padding(start = Spacing.compact, top = Spacing.small, bottom = Spacing.compact).height(androidx.compose.foundation.layout.IntrinsicSize.Min)) {
                        // The branch line that makes this read as a tree and not as a list.
                        Box(Modifier.width(2.dp).fillMaxHeight().background(Ds.selection.value))
                        Column(Modifier.padding(start = Spacing.compact), verticalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
                            for (leaf in node.children) {
                                PlainButton(
                                    { leaf.time?.let { model.play(it); onDismiss() } },
                                    Modifier.fillMaxWidth().heightIn(min = TapTarget).testTag("mindmap.leaf"),
                                    enabled = leaf.time != null && model.hasAudio,
                                ) {
                                    Text(model.display(leaf.title), style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f))
                                    leaf.time?.let { Text(it.clock, style = DsType.timestamp, color = Ds.action.value) }
                                }
                            }
                        }
                    }
                }
                Spacer(Modifier.height(Spacing.compact))
            }
        }
    }
}

