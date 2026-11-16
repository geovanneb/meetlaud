package com.meetlaud.app.feature.models

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.stateDescription
import com.meetlaud.app.designsystem.ActivityBar
import com.meetlaud.app.designsystem.AlertButton
import com.meetlaud.app.designsystem.Choice
import com.meetlaud.app.designsystem.ControlSize
import androidx.compose.ui.semantics.selected
import com.meetlaud.app.designsystem.ChoiceSheet
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.EmptyState
import com.meetlaud.app.designsystem.IosActionSheet
import com.meetlaud.app.designsystem.IosMenu
import com.meetlaud.app.designsystem.ListRow
import com.meetlaud.app.designsystem.ListSection
import com.meetlaud.app.designsystem.ListToggle
import com.meetlaud.app.designsystem.MenuAction
import com.meetlaud.app.designsystem.ProgressRing
import com.meetlaud.app.designsystem.Radius
import com.meetlaud.app.designsystem.RowLabel
import com.meetlaud.app.designsystem.SegmentedControl
import com.meetlaud.app.designsystem.SecondaryAction
import com.meetlaud.app.designsystem.SettingsRowLabel
import com.meetlaud.app.designsystem.SfIcon
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.designsystem.SwipeAction
import com.meetlaud.app.designsystem.SwipeRow
import com.meetlaud.app.designsystem.TextAction
import com.meetlaud.app.designsystem.UsageBar
import com.meetlaud.app.designsystem.UsageDot
import com.meetlaud.app.designsystem.UsagePart
import com.meetlaud.app.designsystem.abbreviatedDateTime
import com.meetlaud.app.designsystem.fileSize
import com.meetlaud.app.feature.shared.AutoTranscribe
import com.meetlaud.app.feature.shared.languageName
import com.meetlaud.app.feature.shared.detail
import com.meetlaud.app.feature.shared.title
import com.meetlaud.app.feature.shared.percent
import com.meetlaud.app.feature.shared.rememberPreference
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.routing.AppRoute
import com.meetlaud.app.routing.LocalRouter
import com.meetlaud.app.shell.Screen
import com.meetlaud.app.shell.contentPadding
import com.meetlaud.domain.AskPreferences
import com.meetlaud.domain.FitLabel
import com.meetlaud.domain.InstallState
import com.meetlaud.domain.ModelFit
import com.meetlaud.domain.ModelRole
import com.meetlaud.domain.ModelRunStat
import com.meetlaud.domain.ModelsSnapshot
import com.meetlaud.domain.Priority
import com.meetlaud.domain.RightNow
import com.meetlaud.domain.SelectionMode
import com.meetlaud.domain.SetupProgress
import com.meetlaud.domain.SpeedEvidence
import com.meetlaud.domain.SummaryPreferences
import kotlinx.coroutines.launch
import java.time.ZoneId

private fun role(raw: String): ModelRole = ModelRole.entries.first { it.raw == raw }

/** A title over its value, as `labeled` in ModelDetailView.swift. */
@Composable
private fun Labeled(title: String, value: String, divider: Boolean = true) {
    ListRow(Modifier.semantics(mergeDescendants = true) {}, divider = divider) {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
            Text(title, style = DsType.meta, color = Ds.secondaryText.value)
            Text(value, style = DsType.rowTitle, color = Ds.primaryText.value)
        }
    }
}

@Composable
private fun TextRow(text: String, color: androidx.compose.ui.graphics.Color = Ds.primaryText.value, style: androidx.compose.ui.text.TextStyle = DsType.rowTitle, modifier: Modifier = Modifier, divider: Boolean = true, enabled: Boolean = true, onClick: (() -> Unit)? = null) {
    ListRow(modifier, divider, onClick = if (enabled) onClick else null) {
        Text(text, style = style, color = if (enabled) color else Ds.secondaryText.value)
    }
}

@Composable
private fun Testing(controller: ModelsController, divider: Boolean = true) {
    ListRow(divider = divider) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
            ProgressRing(null)
            Text(L10n.Models.testing, style = DsType.rowTitle, color = Ds.primaryText.value)
        }
    }
}

/** One place for every model on the device, and the current advice about them. As AIModelsView.swift. */
@Composable
fun AIModelsScreen(controller: ModelsController) {
    val router = LocalRouter.current
    Screen(title = L10n.Models.title, modifier = Modifier.testTag("screen.models")) {
        val snapshot = controller.snapshot
        if (snapshot == null) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { ProgressRing(null) }
            return@Screen
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding()).animateContentSize()) {
            ListSection { ListRow(divider = false) { DeviceCard(snapshot) } }
            // Above anything that depends on it: a choice must not move the control it was made on.
            ListSection(L10n.Models.priority) {
                ListRow(divider = false) { PriorityPicker(snapshot.priority, controller::setPriority) }
            }
            if (snapshot.suggestions.isNotEmpty()) {
                ListSection(L10n.Models.suggestions) {
                    snapshot.suggestions.forEachIndexed { index, suggestion ->
                        SwipeRow(trailing = listOf(SwipeAction(L10n.Models.dismiss, "xmark", Ds.secondaryText.value) { controller.dismiss(suggestion) })) {
                            TextRow(suggestion.title(snapshot), style = DsType.meta, divider = index < snapshot.suggestions.lastIndex)
                        }
                    }
                }
            }
            // While the setup is on its way, its progress takes the place of the button that started it.
            val progress = snapshot.setupProgress
            if (progress != null) {
                ListSection {
                    ListRow(divider = progress.phase == SetupProgress.Phase.PAUSED) { SetupProgressRow(progress) }
                    if (progress.phase == SetupProgress.Phase.PAUSED) {
                        TextRow(L10n.Models.resumeAll, Ds.action.value, modifier = Modifier.testTag("models.resumeAll"), divider = false, onClick = controller::resumeSetup)
                    }
                }
            } else if (snapshot.missingFromSetup.isNotEmpty()) {
                ListSection { TextRow(L10n.Models.downloadAll, Ds.action.value, modifier = Modifier.testTag("models.downloadAll"), divider = false, onClick = controller::installRecommended) }
            }
            ListSection(L10n.Models.functions) {
                ModelRole.entries.forEachIndexed { index, role -> RoleRow(role, snapshot, index < ModelRole.entries.lastIndex) }
            }
            ListSection {
                ListRow(Modifier.testTag("models.storage"), divider = false, onClick = { router.push(AppRoute.ModelStorage) }) { SettingsRowLabel(L10n.Models.storage) }
            }
        }
    }
}

/** The one-tap setup as one line, so a download in the background is never a silent one. */
@Composable
private fun SetupProgressRow(progress: SetupProgress) {
    val received = progress.received.fileSize
    val total = progress.total.fileSize
    val title = when (progress.phase) {
        SetupProgress.Phase.DOWNLOADING -> L10n.Models.setupDownloading(received, total)
        SetupProgress.Phase.PAUSED -> L10n.Models.setupPaused(received, total)
        SetupProgress.Phase.WAITING_FOR_WIFI -> L10n.Models.stateWaitingWiFi
        SetupProgress.Phase.FINISHING -> L10n.Models.setupFinishing
    }
    val value = percent(progress.fraction)
    Column(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) { stateDescription = value }.testTag("models.setupProgress"),
        verticalArrangement = Arrangement.spacedBy(Spacing.small),
    ) {
        Text(title, style = DsType.meta, color = Ds.primaryText.value)
        // The shared bar, as on each model's row. Checking and preparing have no fraction, so it keeps moving.
        ActivityBar(if (progress.phase == SetupProgress.Phase.FINISHING) null else progress.fraction, Modifier.padding(top = Spacing.xSmall).clearAndSetSemantics {})
        if (progress.phase == SetupProgress.Phase.DOWNLOADING) Text(L10n.Models.setupBackground, style = DsType.meta, color = Ds.secondaryText.value)
    }
}

/** Holds its own selection, so the segment slides at once while the saved value comes back in a new snapshot. */
@Composable
private fun PriorityPicker(initial: Priority, onChange: (Priority) -> Unit) {
    var selection by remember { mutableStateOf(initial) }
    SegmentedControl(Priority.entries.map { it.title }, Priority.entries.indexOf(selection), { index ->
        selection = Priority.entries[index]
        onChange(selection)
    }, Modifier.fillMaxWidth(), tags = Priority.entries.map { "models.priority.${it.raw}" })
}

@Composable
private fun DeviceCard(snapshot: ModelsSnapshot) {
    val status = when (snapshot.rightNow) {
        RightNow.Great, is RightNow.Good -> Ds.action.value
        else -> Ds.record.value
    }
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.medium)).background(Ds.surface.value).padding(Spacing.medium).semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(Spacing.small),
    ) {
        Text(snapshot.device.name, style = DsType.heading, color = Ds.primaryText.value)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
            Box(Modifier.size(10.dp).clip(CircleShape).background(status))
            Text(snapshot.rightNow.title, style = DsType.meta, color = Ds.primaryText.value, modifier = Modifier.testTag("models.rightNow"))
        }
        snapshot.rightNow.detail?.let { Text(it, style = DsType.meta, color = Ds.secondaryText.value) }
        val memory = snapshot.device.physicalMemoryMB.toLong() * 1_000_000
        Text(L10n.Models.deviceSummary(memory.fileSize, snapshot.condition.freeBytes.fileSize), style = DsType.meta, color = Ds.secondaryText.value)
    }
}

private val Int.dp get() = androidx.compose.ui.unit.Dp(this.toFloat())

@Composable
private fun RoleRow(role: ModelRole, snapshot: ModelsSnapshot, divider: Boolean) {
    val router = LocalRouter.current
    val fits = snapshot.fits[role].orEmpty()
    if (fits.isEmpty()) {
        // One thing to TalkBack: the function and its state.
        ListRow(Modifier.testTag("models.role.${role.raw}").semantics(mergeDescendants = true) {}, divider) { RowLabel(role.title, L10n.Models.comingLater) }
        return
    }
    val detail = run {
        val pinned = snapshot.selections[role] as? SelectionMode.Pinned
        val pinnedFit = pinned?.let { mode -> fits.firstOrNull { it.model.id == mode.id } }
        if (pinnedFit != null) {
            val state = snapshot.state(pinnedFit.model.id)
            val title = state.title
            return@run if (state.isInFlight && title != null) "${pinnedFit.model.displayName} · $title" else pinnedFit.model.displayName
        }
        val installed = fits.firstOrNull { snapshot.isInstalled(it.model.id) }
        val coming = if (installed == null) fits.firstOrNull { snapshot.state(it.model.id).isInFlight } else null
        coming?.let { snapshot.state(it.model.id).title } ?: installed?.let { L10n.Models.automaticUsing(it.model.displayName) } ?: L10n.Models.notInstalled
    }
    ListRow(Modifier.testTag("models.role.${role.raw}"), divider, onClick = { router.push(AppRoute.ModelRole(role.raw)) }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            RowLabel(role.title, detail, Modifier.weight(1f))
            SfIcon("chevron.right", tint = Ds.secondaryText.value, size = DsType.badge.fontSize)
        }
    }
}

/** Every model for one function, best first. As RoleModelsView.swift. */
@Composable
fun RoleModelsScreen(raw: String, controller: ModelsController) {
    val role = role(raw)
    val router = LocalRouter.current
    var showsAll by remember { mutableStateOf(false) }
    var isChoosingMode by remember { mutableStateOf(false) }
    Screen(title = role.title, modifier = Modifier.testTag("screen.role")) {
        val snapshot = controller.snapshot ?: return@Screen
        val fits = snapshot.fits[role].orEmpty()
        val visible = if (showsAll) fits else fits.filter { it.label != FitLabel.UNSUPPORTED }
        val mode = snapshot.selections[role] ?: SelectionMode.Automatic
        val installed = fits.filter { snapshot.isInstalled(it.model.id) }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding())) {
            ListSection {
                TextRow(role.purpose, Ds.secondaryText.value, DsType.meta)
                ListRow(Modifier.testTag("models.mode"), divider = false, onClick = { isChoosingMode = true }) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(L10n.Models.mode, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f))
                        Box {
                            Text(
                                (mode as? SelectionMode.Pinned)?.let { pinned -> fits.firstOrNull { it.model.id == pinned.id }?.model?.displayName } ?: L10n.Models.automatic,
                                style = DsType.rowTitle, color = Ds.secondaryText.value,
                            )
                            IosMenu(isChoosingMode, { isChoosingMode = false }, listOf(MenuAction(L10n.Models.automatic, isChecked = mode == SelectionMode.Automatic) { controller.select(SelectionMode.Automatic, role) }) +
                                installed.map { fit -> MenuAction(fit.model.displayName, isChecked = (mode as? SelectionMode.Pinned)?.id == fit.model.id) { controller.select(SelectionMode.Pinned(fit.model.id), role) } })
                        }
                    }
                }
            }
            ListSection {
                visible.forEachIndexed { index, fit ->
                    ListRow(Modifier.testTag("model.${fit.model.id}"), divider = index < visible.lastIndex, onClick = { router.push(AppRoute.ModelDetail(fit.model.id, role.raw)) }) {
                        ModelRow(fit, snapshot.state(fit.model.id))
                    }
                }
            }
            if (fits.size != visible.size || visible.size > 1) {
                ListSection {
                    if (fits.size != visible.size) TextRow(L10n.Models.showAll, Ds.action.value, divider = visible.size > 1) { showsAll = true }
                    if (visible.size > 1) {
                        ListRow(Modifier.testTag("models.compare"), divider = false, onClick = { router.push(AppRoute.CompareModels(role.raw, showsAll)) }) { SettingsRowLabel(L10n.Models.compare) }
                    }
                }
            }
        }
    }
}

@Composable
private fun ModelRow(fit: ModelFit, state: InstallState) {
    val detail = listOf(if (fit.model.isSystemManaged) L10n.Models.managedByIOS else fit.model.totalBytes.fileSize, state.title ?: fit.label.title).joinToString(" · ")
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}.animateContentSize(), verticalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.small), verticalAlignment = Alignment.CenterVertically) {
                Text(fit.model.displayName, style = DsType.rowTitle, color = Ds.primaryText.value)
                if (fit.label == FitLabel.BEST) Text(fit.label.title, style = DsType.badge, color = Ds.action.value)
            }
            Text(detail, style = DsType.meta, color = Ds.secondaryText.value)
            if (state.isWorking) ActivityBar(state.progress, Modifier.padding(top = Spacing.xSmall))
        }
        SfIcon("chevron.right", tint = Ds.secondaryText.value, size = DsType.badge.fontSize)
    }
}

/** The models for one function side by side, in the words used everywhere else. As CompareModelsView. */
@Composable
fun CompareModelsScreen(raw: String, showsAll: Boolean, controller: ModelsController) {
    val role = role(raw)
    val scope = rememberCoroutineScope()
    var isChoosingRecording by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { controller.loadTrialChoices() }
    DisposableEffect(Unit) { onDispose { controller.cancelSpeedTest() } }
    Screen(title = L10n.Models.compare, modifier = Modifier.testTag("screen.compareModels")) {
        val snapshot = controller.snapshot ?: return@Screen
        val all = snapshot.fits[role].orEmpty()
        val fits = if (showsAll) all else all.filter { it.label != FitLabel.UNSUPPORTED }
        val installed = fits.filter { snapshot.isInstalled(it.model.id) }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding())) {
            if (role == ModelRole.TRANSCRIPTION && installed.size > 1) {
                ListSection(L10n.Models.tryTitle) {
                    TextRow(L10n.Models.tryHint, Ds.secondaryText.value, DsType.meta)
                    when {
                        controller.testing != null -> Testing(controller)
                        controller.trialChoices.isEmpty() -> TextRow(L10n.Models.tryNoRecording, Ds.secondaryText.value)
                        else -> {
                            ListRow(Modifier.testTag("models.tryRecording"), onClick = { isChoosingRecording = true }) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(L10n.Models.tryRecording, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f))
                                    Box {
                                        val chosen = controller.trialChoices.firstOrNull { it.id == controller.trialRecording }
                                        Text(chosen?.let(::choiceTitle) ?: "", style = DsType.rowTitle, color = Ds.secondaryText.value, maxLines = 1)
                                        IosMenu(isChoosingRecording, { isChoosingRecording = false }, controller.trialChoices.map { recording ->
                                            MenuAction(choiceTitle(recording), isChecked = recording.id == controller.trialRecording) { controller.trialRecording = recording.id }
                                        })
                                    }
                                }
                            }
                            ListRow {
                                SecondaryAction(L10n.Models.tryRun, Modifier.testTag("models.try"), size = ControlSize.REGULAR) { controller.runTrial(installed.take(2).map { it.model.id }) }
                            }
                        }
                    }
                    controller.testError?.let { TextRow(it, Ds.record.value) }
                    controller.trials.forEachIndexed { index, trial ->
                        ListRow(divider = index < controller.trials.lastIndex) {
                            Column(verticalArrangement = Arrangement.spacedBy(Spacing.small)) {
                                RowLabel(fits.firstOrNull { it.model.id == trial.modelID }?.model?.displayName ?: trial.modelID, L10n.Models.tryTime(Math.round(trial.seconds).toInt()))
                                SelectionContainer { Text(trial.text, style = DsType.meta, color = Ds.primaryText.value, modifier = Modifier.testTag("models.trialText")) }
                                SecondaryAction(L10n.Models.tryUse, Modifier.testTag("models.tryUse"), size = ControlSize.SMALL) { controller.select(SelectionMode.Pinned(trial.modelID), role) }
                            }
                        }
                    }
                }
            }
            for (fit in fits) {
                ListSection(fit.model.displayName) {
                    val rows = buildList {
                        add(L10n.Models.fit to fit.reason.title)
                        add(L10n.Models.speed to fit.speed.title)
                        if (!fit.model.isSystemManaged) add(L10n.Models.size to fit.model.totalBytes.fileSize)
                        if (fit.model.languages.isNotEmpty()) add(L10n.Models.languages to fit.model.languages.joinToString(", ") { languageName(it) })
                    }
                    rows.forEachIndexed { index, (title, value) ->
                        ListRow(divider = index < rows.lastIndex) {
                            Row(Modifier.semantics(mergeDescendants = true) {}) {
                                Text(title, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f))
                                Spacer(Modifier.width(Spacing.small))
                                Text(value, style = DsType.rowTitle, color = Ds.secondaryText.value, textAlign = androidx.compose.ui.text.style.TextAlign.End)
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun choiceTitle(recording: com.meetlaud.domain.Recording): String {
    val day = recording.createdAt.atZone(ZoneId.systemDefault()).toLocalDate()
    return "${recording.title} · ${java.time.format.DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.MEDIUM).withLocale(com.meetlaud.app.localization.Strings.locale()).format(day)}"
}

/** One model: what it is, getting it, and how fast it runs here. As ModelDetailView.swift. */
@Composable
fun ModelDetailScreen(modelID: String, raw: String, controller: ModelsController) {
    val role = role(raw)
    var isConfirmingDelete by remember { mutableStateOf(false) }
    val fit = controller.snapshot?.fits?.get(role)?.firstOrNull { it.model.id == modelID }
    val state = controller.snapshot?.state(modelID) ?: InstallState.NotInstalled
    LaunchedEffect(controller.lastTest) { controller.loadHistory(modelID) }
    Screen(title = fit?.model?.displayName ?: "", modifier = Modifier.testTag("screen.modelDetail")) {
        fit ?: return@Screen
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding()).animateContentSize()) {
            ListSection {
                Labeled(L10n.Models.fit, fit.reason.title)
                Labeled(L10n.Models.speed, fit.speed.title)
                if (!fit.model.isSystemManaged) Labeled(L10n.Models.size, fit.model.totalBytes.fileSize)
                if (fit.model.languages.isNotEmpty()) Labeled(L10n.Models.languages, fit.model.languages.joinToString(", ") { languageName(it) })
                Labeled(L10n.Models.license, fit.model.license, divider = fit.model.qualityIsProvisional)
                if (fit.model.qualityIsProvisional) TextRow(L10n.Models.qualityProvisional, Ds.secondaryText.value, DsType.meta, divider = false)
            }
            ListSection { Actions(fit, state, controller) { isConfirmingDelete = true } }
            if (state == InstallState.Ready) {
                when {
                    // Speakers have no clip to run yet.
                    ModelRole.TRANSCRIPTION in fit.model.roles -> {
                        SpeedTest(modelID, controller)
                        if (controller.history.isNotEmpty()) History(controller.history)
                    }
                    ModelRole.CHAT in fit.model.roles -> LanguageTest(modelID, controller)
                    ModelRole.SEARCH in fit.model.roles -> SearchTest(modelID, controller)
                }
            }
        }
    }
    if (isConfirmingDelete) {
        IosActionSheet(
            L10n.Models.deleteConfirm,
            actions = listOf(AlertButton(L10n.Library.delete, AlertButton.Role.DESTRUCTIVE) { controller.remove(modelID) }, AlertButton(L10n.Common.cancel, AlertButton.Role.CANCEL)),
            onDismiss = { isConfirmingDelete = false },
        )
    }
}

@Composable
private fun Actions(fit: ModelFit, state: InstallState, controller: ModelsController, onDelete: () -> Unit) {
    val rows = mutableListOf<@Composable (Boolean) -> Unit>()
    state.title?.let { title ->
        rows += { divider ->
            ListRow(Modifier.semantics(mergeDescendants = true) {}.testTag("model.state"), divider) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
                    if (state.isWorking) ProgressRing(state.progress)
                    Text(title, style = DsType.rowTitle, color = Ds.primaryText.value)
                }
            }
        }
    }
    if (state.isWorking) rows += { divider -> ListRow(divider = divider) { ActivityBar(state.progress) } }
    when (state) {
        InstallState.NotInstalled, is InstallState.Failed -> if (fit.label != FitLabel.UNSUPPORTED) {
            rows += { divider -> TextRow(if (fit.model.isSystemManaged) L10n.Models.install else L10n.Models.download, Ds.action.value, modifier = Modifier.testTag("model.download"), divider = divider) { controller.install(fit.model) } }
        }
        is InstallState.Downloading, InstallState.Queued, InstallState.WaitingForWiFi -> {
            rows += { divider -> TextRow(L10n.Recorder.pause, Ds.action.value, divider = divider) { controller.pause(fit.model.id) } }
            rows += { divider -> TextRow(L10n.Common.cancel, Ds.record.value, divider = divider) { controller.cancel(fit.model.id) } }
        }
        is InstallState.Paused -> {
            rows += { divider -> TextRow(L10n.Recorder.resume, Ds.action.value, divider = divider) { controller.install(fit.model) } }
            rows += { divider -> TextRow(L10n.Common.cancel, Ds.record.value, divider = divider) { controller.cancel(fit.model.id) } }
        }
        InstallState.Ready -> if (!fit.model.isSystemManaged) {
            rows += { divider -> TextRow(L10n.Library.delete, Ds.record.value, modifier = Modifier.testTag("model.delete"), divider = divider, onClick = onDelete) }
        }
        InstallState.Verifying, InstallState.Preparing, InstallState.SelfTest -> Unit
    }
    rows.forEachIndexed { index, row -> row(index < rows.lastIndex) }
}

@Composable
private fun TestError(controller: ModelsController) {
    controller.testError?.let { TextRow(it, Ds.record.value, modifier = Modifier.testTag("model.testError")) }
}

@Composable
private fun SpeedTest(modelID: String, controller: ModelsController) {
    ListSection(L10n.Models.speedTest) {
        if (controller.testing == modelID) {
            Testing(controller)
            TextRow(L10n.Common.cancel, Ds.action.value) { controller.cancelSpeedTest() }
        } else {
            val idle = controller.testing == null
            TextRow(L10n.Models.quickTest, Ds.action.value, modifier = Modifier.testTag("model.quickTest"), enabled = idle) { controller.runSpeedTest(modelID, sustained = false) }
            TextRow(L10n.Models.sustainedTest, Ds.action.value, enabled = idle) { controller.runSpeedTest(modelID, sustained = true) }
            TextRow(L10n.Models.sustainedHint, Ds.secondaryText.value, DsType.meta)
        }
        TestError(controller)
        controller.lastTest?.takeIf { it.modelID == modelID }?.let {
            TextRow(SpeedEvidence.Measured(it.speedX).title, modifier = Modifier.testTag("model.testResult"), divider = false)
        }
    }
}

@Composable
private fun LanguageTest(modelID: String, controller: ModelsController) {
    ListSection(L10n.Models.speedTest) {
        if (controller.testing == modelID) {
            Testing(controller)
            TextRow(L10n.Common.cancel, Ds.action.value) { controller.cancelSpeedTest() }
        } else {
            TextRow(L10n.Models.quickTest, Ds.action.value, modifier = Modifier.testTag("model.quickTest"), enabled = controller.testing == null) { controller.runLanguageTest(modelID) }
        }
        TestError(controller)
        controller.lastLanguageTest?.takeIf { it.modelID == modelID }?.let {
            TextRow(L10n.Models.writingSpeed(it.wordsPerMinute), modifier = Modifier.testTag("model.testResult"), divider = false)
        }
    }
}

@Composable
private fun SearchTest(modelID: String, controller: ModelsController) {
    ListSection(L10n.Models.speedTest) {
        if (controller.testing == modelID) {
            Testing(controller)
        } else {
            TextRow(L10n.Models.quickTest, Ds.action.value, modifier = Modifier.testTag("model.quickTest"), enabled = controller.testing == null) { controller.runSearchTest(modelID) }
        }
        TestError(controller)
        controller.lastSearchTest?.takeIf { it.modelID == modelID }?.let {
            TextRow(L10n.Models.searchSpeed(it.secondsPerHourOfAudio), modifier = Modifier.testTag("model.testResult"), divider = false)
        }
    }
}

@Composable
private fun History(runs: List<ModelRunStat>) {
    ListSection(L10n.Models.history, modifier = Modifier.testTag("model.history")) {
        runs.forEachIndexed { index, run ->
            ListRow(divider = index < runs.lastIndex) {
                RowLabel(if (run.outcome == ModelRunStat.Outcome.KILLED) com.meetlaud.app.localization.PlatformText.runStopped else SpeedEvidence.Measured(run.speedX).title, run.date.abbreviatedDateTime())
            }
        }
    }
}

/** What the downloaded models take, largest first. As StorageView.swift. */
@Composable
fun ModelStorageScreen(controller: ModelsController) {
    val snapshot = controller.snapshot
    val installed = remember(snapshot) {
        val seen = HashSet<String>()
        snapshot?.fits?.values?.flatten()?.map { it.model }
            ?.filter { snapshot.isInstalled(it.id) && !it.isSystemManaged && seen.add(it.id) }
            ?.sortedByDescending { it.totalBytes }.orEmpty()
    }
    Screen(title = L10n.Models.storage, modifier = Modifier.testTag("screen.modelStorage")) {
        if (installed.isEmpty()) {
            EmptyState(L10n.Models.noModels, L10n.Models.storageNote, "internaldrive")
            return@Screen
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding())) {
            ListSection {
                // Which model takes the most, at a glance, before reading the rows.
                ListRow(Modifier.testTag("models.storageUsage"), divider = false) {
                    Column(Modifier.padding(vertical = Spacing.small), verticalArrangement = Arrangement.spacedBy(Spacing.compact)) {
                        Text(L10n.Models.storageTotal(installed.sumOf { it.totalBytes }.fileSize), style = DsType.heading, color = Ds.primaryText.value)
                        UsageBar(installed.map { UsagePart(it.id, it.displayName, it.totalBytes, it.totalBytes.fileSize) }, showsLegend = false)
                    }
                }
            }
            ListSection(footer = L10n.Models.storageNote) {
                installed.forEachIndexed { index, model ->
                    SwipeRow(trailing = listOf(SwipeAction(L10n.Library.delete, "trash", Ds.record.value) { controller.remove(model.id) })) {
                        ListRow(Modifier.semantics(mergeDescendants = true) {}, divider = index < installed.lastIndex) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
                                UsageDot(index)
                                Text(model.displayName, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f))
                                Text(model.totalBytes.fileSize, style = DsType.rowTitle, color = Ds.secondaryText.value)
                            }
                        }
                    }
                }
            }
        }
    }
}

/** Every connection the app made, which can only be a model download (D-004). As NetworkActivityView. */
@Composable
fun NetworkActivityScreen(controller: ModelsController) {
    val scope = rememberCoroutineScope()
    var isConfirmingClear by remember { mutableStateOf(false) }
    // After a clear, "nothing has left this device" would no longer be true.
    var clearedAt by rememberPreference("network.clearedAt", 0.0)
    LaunchedEffect(Unit) { controller.refreshNetworkLog() }
    Screen(
        title = L10n.Models.networkActivity,
        modifier = Modifier.testTag("screen.network"),
        trailing = {
            if (controller.networkLog.isNotEmpty()) TextAction(L10n.Models.clearNetworkLog, Modifier.testTag("network.clear"), color = Ds.primaryText.value) { isConfirmingClear = true }
        },
    ) {
        if (controller.networkLog.isEmpty()) {
            EmptyState(if (clearedAt > 0) L10n.Models.networkClearedTitle else L10n.Models.networkEmptyTitle, L10n.Models.networkNote, "checkmark.shield")
            return@Screen
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding())) {
            ListSection(footer = L10n.Models.networkNote) {
                controller.networkLog.forEachIndexed { index, entry ->
                    ListRow(Modifier.semantics(mergeDescendants = true) {}, divider = index < controller.networkLog.lastIndex) {
                        RowLabel(entry.host, listOf(entry.modelID, entry.bytes.fileSize, entry.date.abbreviatedDateTime()).joinToString(" · "))
                    }
                }
            }
        }
    }
    if (isConfirmingClear) {
        IosActionSheet(
            L10n.Models.clearNetworkLogConfirm,
            actions = listOf(
                AlertButton(L10n.Models.clearNetworkLog, AlertButton.Role.DESTRUCTIVE) {
                    clearedAt = System.currentTimeMillis() / 1000.0
                    scope.launch { controller.clearNetworkLog() }
                },
                AlertButton(L10n.Common.cancel, AlertButton.Role.CANCEL),
            ),
            onDismiss = { isConfirmingClear = false },
        )
    }
}

private val SUPPORTED_LANGUAGES = listOf("en", "ja", "pt", "es")

/** How the app behaves, as PreferencesView.swift. */
@Composable
fun PreferencesScreen(controller: ModelsController) {
    val router = LocalRouter.current
    var auto by rememberPreference(AutoTranscribe.STORAGE_KEY, AutoTranscribe.ASK.raw)
    var autoSummary by rememberPreference(SummaryPreferences.AUTO_KEY, false)
    var profile by rememberPreference(SummaryPreferences.PROFILE_KEY, "")
    var promptBar by rememberPreference(AskPreferences.PROMPT_BAR_KEY, AskPreferences.PromptBar.FOCUS.raw)
    var isChoosingAuto by remember { mutableStateOf(false) }
    var isChoosingPromptBar by remember { mutableStateOf(false) }
    fun toggle(code: String) {
        val languages = controller.languages.toMutableList()
        if (code in languages) {
            if (languages.size <= 1) return
            languages.remove(code)
        } else {
            languages.add(code)
        }
        controller.changeLanguages(languages)
    }
    Screen(title = L10n.Settings.preferences, modifier = Modifier.testTag("screen.preferences")) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding())) {
            ListSection(L10n.Transcript.title) {
                ListRow(Modifier.testTag("preferences.auto"), onClick = { isChoosingAuto = true }) { SettingsRowLabel(L10n.Transcript.autoLabel, value = AutoTranscribe.from(auto).title) }
                ListRow(Modifier.testTag("preferences.vocabulary"), divider = false, onClick = { router.push(AppRoute.Vocabulary) }) { SettingsRowLabel(L10n.Vocabulary.title) }
            }
            ListSection(L10n.Summary.title, L10n.Summary.autoNote) {
                ListToggle(L10n.Summary.auto, autoSummary, { autoSummary = it }, Modifier.testTag("preferences.autoSummary"), divider = false)
            }
            ListSection(L10n.Summary.profile, L10n.Summary.profileNote(profile.length, SummaryPreferences.PROFILE_LIMIT)) {
                ListRow(Modifier.testTag("preferences.profile"), divider = false) {
                    Box(Modifier.fillMaxWidth()) {
                        if (profile.isEmpty()) Text(L10n.Summary.profileHint, style = DsType.rowTitle, color = Ds.secondaryText.value)
                        androidx.compose.foundation.text.BasicTextField(
                            profile, { profile = it.take(SummaryPreferences.PROFILE_LIMIT) }, Modifier.fillMaxWidth(),
                            textStyle = DsType.rowTitle.copy(color = Ds.primaryText.value), minLines = 3, maxLines = 8,
                            cursorBrush = androidx.compose.ui.graphics.SolidColor(Ds.action.value),
                        )
                    }
                }
            }
            ListSection(L10n.Nav.ask) {
                ListRow(Modifier.testTag("preferences.promptBar"), onClick = { isChoosingPromptBar = true }) {
                    SettingsRowLabel(L10n.Ask.promptBar, value = if (promptBar == AskPreferences.PromptBar.FOCUS.raw) L10n.Ask.promptFocus else L10n.Ask.promptNew)
                }
                ListRow(Modifier.testTag("preferences.memory"), divider = false, onClick = { router.push(AppRoute.Memory) }) { SettingsRowLabel(L10n.Ask.memory) }
            }
            // Widgets are iPhone only for now, so their setting waits until Android has them (docs/android.md).
            ListSection(L10n.Models.spokenLanguages) {
                SUPPORTED_LANGUAGES.forEachIndexed { index, code ->
                    val isOn = code in controller.languages
                    val name = languageName(code)
                    ListRow(Modifier.semantics { contentDescription = name; selected = isOn }, divider = index < SUPPORTED_LANGUAGES.lastIndex, onClick = { toggle(code) }) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(name, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f))
                            if (isOn) SfIcon("checkmark", tint = Ds.action.value)
                        }
                    }
                }
            }
        }
    }
    if (isChoosingAuto) {
        ChoiceSheet(L10n.Transcript.autoLabel, L10n.Common.close, AutoTranscribe.entries.map { Choice(it.raw, it.title) }, auto, { auto = it }, onDismiss = { isChoosingAuto = false })
    }
    if (isChoosingPromptBar) {
        ChoiceSheet(
            L10n.Ask.promptBar, L10n.Common.close,
            listOf(Choice(AskPreferences.PromptBar.FOCUS.raw, L10n.Ask.promptFocus), Choice(AskPreferences.PromptBar.NEW_CHAT.raw, L10n.Ask.promptNew)),
            promptBar, { promptBar = it }, onDismiss = { isChoosingPromptBar = false },
        )
    }
}


/** The one-tap setup. It names functions, not models, because that is what people care about. As ModelSetupView. */
@Composable
fun ModelSetupSheet(controller: ModelsController, onCustomize: () -> Unit) {
    val dismiss = { controller.showsSetup = false }
    com.meetlaud.app.designsystem.IosSheet(dismiss, large = false) {
        Column(Modifier.fillMaxWidth().padding(Spacing.large), verticalArrangement = Arrangement.spacedBy(Spacing.large)) {
            com.meetlaud.app.designsystem.MeetlaudMark(36.dp)
            Text(L10n.Models.setupTitle, style = DsType.pageTitle, color = Ds.primaryText.value, modifier = Modifier.semantics { heading() })
            controller.snapshot?.let { snapshot ->
                Text(L10n.Models.setupFor(snapshot.device.name), style = DsType.rowTitle, color = Ds.secondaryText.value)
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.small)) {
                    for (role in ModelRole.entries.filter { snapshot.fits[it].orEmpty().isNotEmpty() }) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
                            SfIcon("checkmark", tint = Ds.action.value)
                            Text(role.title, style = DsType.rowTitle, color = Ds.primaryText.value)
                        }
                    }
                }
                val total = snapshot.missingFromSetup.sumOf { it.totalBytes }
                Text(L10n.Models.setupSize(total.fileSize, snapshot.condition.freeBytes.fileSize), style = DsType.meta, color = Ds.secondaryText.value)
                Text(L10n.Models.setupNote, style = DsType.meta, color = Ds.secondaryText.value)
            }
            com.meetlaud.app.designsystem.PrimaryAction(L10n.Models.downloadAll, Modifier.fillMaxWidth().testTag("setup.download")) {
                controller.installRecommended()
                dismiss()
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                TextAction(L10n.Models.customize, Modifier.testTag("setup.customize")) {
                    dismiss()
                    onCustomize()
                }
                Spacer(Modifier.weight(1f))
                TextAction(L10n.Models.notNow, Modifier.testTag("setup.notNow"), onClick = dismiss)
            }
        }
    }
}
