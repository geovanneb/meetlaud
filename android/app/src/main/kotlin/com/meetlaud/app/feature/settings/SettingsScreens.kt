package com.meetlaud.app.feature.settings

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.meetlaud.app.designsystem.ActivityBar
import com.meetlaud.app.designsystem.AlertButton
import com.meetlaud.app.designsystem.Choice
import com.meetlaud.app.designsystem.ChoiceSheet
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.EmptyState
import com.meetlaud.app.designsystem.FormButton
import com.meetlaud.app.designsystem.FormRow
import com.meetlaud.app.designsystem.FormSection
import com.meetlaud.app.designsystem.FormTextField
import com.meetlaud.app.designsystem.FormToggle
import com.meetlaud.app.designsystem.GlassCircleButton
import com.meetlaud.app.designsystem.IosMenu
import com.meetlaud.app.designsystem.IosSheet
import com.meetlaud.app.designsystem.ListRow
import com.meetlaud.app.designsystem.ListSection
import com.meetlaud.app.designsystem.ListToggle
import com.meetlaud.app.designsystem.MenuAction
import com.meetlaud.app.designsystem.ProgressRing
import com.meetlaud.app.designsystem.Radius
import com.meetlaud.app.designsystem.RowLabel
import com.meetlaud.app.designsystem.SettingsRowLabel
import com.meetlaud.app.designsystem.SheetBar
import com.meetlaud.app.designsystem.SheetBody
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.designsystem.SwipeAction
import com.meetlaud.app.designsystem.SwipeRow
import com.meetlaud.app.designsystem.TextAction
import com.meetlaud.app.designsystem.UsageBar
import com.meetlaud.app.designsystem.UsagePart
import com.meetlaud.app.designsystem.fileSize
import com.meetlaud.app.feature.shared.AppLockController
import com.meetlaud.app.feature.shared.LocalPreferences
import com.meetlaud.app.feature.shared.percent
import com.meetlaud.app.feature.shared.rememberPreference
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.localization.PlatformText
import com.meetlaud.app.routing.AppRoute
import com.meetlaud.app.routing.Destination
import com.meetlaud.app.routing.LocalRouter
import com.meetlaud.app.shell.Screen
import com.meetlaud.app.shell.contentPadding
import com.meetlaud.domain.AppTheme
import com.meetlaud.domain.CalendarAccess
import com.meetlaud.domain.CalendarChoices
import com.meetlaud.domain.CalendarProvider
import com.meetlaud.domain.CalendarSource
import com.meetlaud.domain.Folder
import com.meetlaud.domain.FolderID
import com.meetlaud.domain.NotificationPreferences
import com.meetlaud.domain.ThemePreferences
import com.meetlaud.domain.VocabularyEntry
import com.meetlaud.domain.VocabularyPreferences
import com.meetlaud.domain.localizedStandardCompare
import kotlinx.coroutines.launch
import java.io.File

private fun openAppSettings(context: android.content.Context) {
    context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

val AppTheme.title: String
    get() = when (this) {
        AppTheme.SYSTEM -> L10n.System.themeSystem
        AppTheme.LIGHT -> L10n.System.themeLight
        AppTheme.DARK -> L10n.System.themeDark
    }

private val AppTheme.symbol: String
    get() = when (this) {
        AppTheme.SYSTEM -> "circle.lefthalf.filled"
        AppTheme.LIGHT -> "sun.max"
        AppTheme.DARK -> "moon"
    }

/** Settings, as SettingsView.swift. */
@Composable
fun SettingsScreen() {
    val router = LocalRouter.current
    val context = LocalContext.current
    var theme by rememberPreference(ThemePreferences.KEY, AppTheme.SYSTEM.raw)
    var isChoosingTheme by remember { mutableStateOf(false) }
    @Composable
    fun Row(title: String, symbol: String, route: AppRoute, tag: String, divider: Boolean = true) {
        ListRow(Modifier.testTag("settings.$tag"), divider, onClick = { router.push(route) }) { SettingsRowLabel(title, symbol = symbol) }
    }
    Screen(title = L10n.Nav.settings, modifier = Modifier.testTag("screen.settings")) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding())) {
            ListSection(L10n.Settings.workspace) {
                Row(L10n.Settings.preferences, "slider.horizontal.3", AppRoute.Preferences, "preferences")
                Row(L10n.Models.title, "cpu", AppRoute.ModelSettings, "models")
                Row(L10n.People.title, "person.2", AppRoute.People, "people")
                Row(L10n.Calendars.title, "calendar", AppRoute.Calendars, "calendars")
                Row(L10n.System.storageTitle, "externaldrive", AppRoute.Storage, "storage", divider = false)
            }
            ListSection(L10n.System.general) {
                Row(L10n.System.notificationsTitle, "bell", AppRoute.Notifications, "notifications")
                ListRow(Modifier.testTag("settings.theme"), onClick = { isChoosingTheme = true }) {
                    SettingsRowLabel(L10n.System.themeTitle, symbol = "circle.lefthalf.filled", value = AppTheme.from(theme).title)
                }
                // Android keeps each app's language in Settings, and that is the one place it should change.
                ListRow(Modifier.testTag("settings.language"), divider = false, onClick = {
                    val intent = if (Build.VERSION.SDK_INT >= 33) Intent(Settings.ACTION_APP_LOCALE_SETTINGS, Uri.fromParts("package", context.packageName, null)) else null
                    intent?.let { context.startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } ?: openAppSettings(context)
                }) { SettingsRowLabel(L10n.System.language, symbol = "globe") }
            }
            ListSection(L10n.Settings.privacy) {
                Row(L10n.System.privacyTitle, "lock.shield", AppRoute.Privacy, "privacy")
                Row(L10n.Models.networkActivity, "network", AppRoute.NetworkActivity, "network", divider = false)
            }
            ListSection(L10n.Nav.help) {
                Row(L10n.System.helpCenter, "questionmark.circle", AppRoute.HelpCenter, "help")
                Row(L10n.System.about, "info.circle", AppRoute.About, "about")
                Row(L10n.System.licenses, "doc.plaintext", AppRoute.Licenses, "licenses", divider = false)
            }
        }
    }
    if (isChoosingTheme) {
        ChoiceSheet(
            L10n.System.themeTitle, L10n.Common.close,
            AppTheme.entries.map { Choice(it.raw, it.title, it.symbol, "theme.${it.raw}") },
            theme, { theme = it }, onDismiss = { isChoosingTheme = false },
        )
    }
}

@Composable
fun NotificationsScreen(controller: SystemController) {
    val scope = rememberCoroutineScope()
    var transcriptReady by rememberPreference(NotificationPreferences.TRANSCRIPT_READY_KEY, false)
    var eventReminders by rememberPreference(NotificationPreferences.EVENT_REMINDERS_KEY, false)
    /** Asks for permission at the moment it is needed, and stays off if the answer is no. */
    fun guarded(wanted: Boolean, set: (Boolean) -> Unit) {
        if (!wanted) set(false) else scope.launch { set(controller.requestNotificationAccess()) }
    }
    Screen(title = L10n.System.notificationsTitle, modifier = Modifier.testTag("screen.notifications")) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding())) {
            ListSection(footer = L10n.System.notifyNote) {
                ListToggle(L10n.System.notifyTranscript, transcriptReady, { guarded(it) { value -> transcriptReady = value } }, Modifier.testTag("notifications.transcript"))
                ListToggle(L10n.System.notifyEvents, eventReminders, { guarded(it) { value -> eventReminders = value } }, Modifier.testTag("notifications.events"), divider = false)
            }
        }
    }
}

/** An SPDX identifier, the same in every language. */
private const val LICENSE_ID = "Apache-2.0"

@Composable
fun AboutScreen(version: String) {
    Screen(title = L10n.System.about, modifier = Modifier.testTag("screen.about")) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding())) {
            ListSection(footer = L10n.System.aboutNote) {
                ListRow { Row { Text(L10n.System.version, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f)); Text(version, style = DsType.rowTitle, color = Ds.secondaryText.value) } }
                ListRow(divider = false) { Row { Text(L10n.System.license, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f)); Text(LICENSE_ID, style = DsType.rowTitle, color = Ds.secondaryText.value) } }
            }
        }
    }
}

/** The parts of a Markdown document a phone lays out itself, as MarkdownBlocks.swift. */
sealed interface MarkdownBlock {
    data class Title(val text: String) : MarkdownBlock
    data class Heading(val text: String) : MarkdownBlock
    data class Paragraph(val text: String) : MarkdownBlock
    data class Bullet(val text: String) : MarkdownBlock
    data class Table(val rows: List<List<String>>) : MarkdownBlock

    companion object {
        fun parse(text: String): List<MarkdownBlock> {
            val blocks = mutableListOf<MarkdownBlock>()
            var rows = mutableListOf<List<String>>()
            fun closeTable() {
                // The first row names the columns, which the layout does not need.
                if (rows.isNotEmpty()) blocks.add(Table(rows.drop(1)))
                rows = mutableListOf()
            }
            for (line in text.lines()) {
                val trimmed = line.trim()
                if (trimmed.startsWith("|")) {
                    val cells = trimmed.trim('|').split("|").map { it.trim() }
                    if (!cells.all { cell -> cell.isNotEmpty() && cell.all { it in "-:" } }) rows.add(cells)
                    continue
                }
                closeTable()
                when {
                    trimmed.startsWith("## ") -> blocks.add(Heading(trimmed.drop(3)))
                    trimmed.startsWith("# ") -> blocks.add(Title(trimmed.drop(2)))
                    trimmed.startsWith("- ") -> blocks.add(Bullet(trimmed.drop(2)))
                    trimmed.isNotEmpty() -> blocks.add(Paragraph(trimmed))
                }
            }
            closeTable()
            return blocks
        }

        /** Links and emphasis: the markers come out, as AttributedString(markdown:) renders them. */
        fun inline(text: String): String =
            text.replace(Regex("\\[([^\\]]+)\\]\\([^)]+\\)"), "$1").replace("**", "").replace("`", "")
    }
}

/** A document that ships inside the app, shown from its Markdown: the licenses, or the privacy policy. */
@Composable
fun DocumentScreen(title: String, text: String, tag: String) {
    val blocks = remember(text) { MarkdownBlock.parse(text) }
    Screen(title = title, modifier = Modifier.testTag(tag)) {
        SelectionContainer {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(Spacing.medium), verticalArrangement = Arrangement.spacedBy(Spacing.compact)) {
                for (block in blocks) {
                    when (block) {
                        is MarkdownBlock.Title -> Text(MarkdownBlock.inline(block.text), style = DsType.pageTitle, color = Ds.primaryText.value, modifier = Modifier.semantics { heading() })
                        is MarkdownBlock.Heading -> Text(MarkdownBlock.inline(block.text), style = DsType.heading, color = Ds.primaryText.value, modifier = Modifier.padding(top = Spacing.compact).semantics { heading() })
                        is MarkdownBlock.Paragraph -> Text(MarkdownBlock.inline(block.text), style = DsType.meta, color = Ds.secondaryText.value)
                        is MarkdownBlock.Bullet -> Text(MarkdownBlock.inline(block.text), style = DsType.meta, color = Ds.primaryText.value, modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.medium)).background(Ds.surface.value).padding(Spacing.compact))
                        is MarkdownBlock.Table -> Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.medium)).background(Ds.surface.value)) {
                            block.rows.forEachIndexed { index, row ->
                                if (index > 0) HorizontalDivider(thickness = 0.5.dp, color = Ds.separator.value)
                                Column(Modifier.fillMaxWidth().padding(Spacing.compact).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
                                    Text(MarkdownBlock.inline(row.firstOrNull() ?: ""), style = DsType.rowTitle, color = Ds.primaryText.value)
                                    for (cell in row.drop(1)) Text(MarkdownBlock.inline(cell), style = DsType.meta, color = Ds.secondaryText.value)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun HelpScreen() {
    val topics = listOf(
        L10n.System.helpRecordTitle to L10n.System.helpRecordBody,
        L10n.System.helpConsentTitle to L10n.System.helpConsentBody,
        L10n.System.helpModelsTitle to L10n.System.helpModelsBody,
        L10n.System.helpAskTitle to L10n.System.helpAskBody,
        // The Action Button and Siri topic is iPhone only. Android's shortcuts are on the roadmap (docs/android.md).
        L10n.System.helpMoveTitle to L10n.System.helpMoveBody,
    )
    Screen(title = L10n.Nav.help, modifier = Modifier.testTag("screen.help")) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding())) {
            for ((title, body) in topics) {
                ListSection(title) { ListRow(divider = false) { Text(body, style = DsType.rowTitle, color = Ds.primaryText.value) } }
            }
        }
    }
}

@Composable
fun PrivacySecurityScreen(controller: SystemController, lock: AppLockController) {
    val router = LocalRouter.current
    val scope = rememberCoroutineScope()
    var isErasing by remember { mutableStateOf(false) }
    Screen(title = L10n.System.privacyTitle, modifier = Modifier.testTag("screen.privacy")) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding())) {
            ListSection(L10n.System.security, if (lock.canLock) PlatformText.appLockNote else PlatformText.appLockUnavailable) {
                ListToggle(L10n.System.appLock, lock.state.isEnabled, { value -> scope.launch { lock.setEnabled(value) } }, Modifier.testTag("privacy.lock"), enabled = lock.canLock, divider = false)
            }
            // Showing meetings in the system's search is iPhone only for now: the Android counterpart is on the roadmap,
            // and a switch that does nothing would mislead (docs/android.md).
            ListSection(L10n.System.promiseTitle) {
                ListRow(Modifier.testTag("privacy.promise")) { Text(PlatformText.promiseBody, style = DsType.rowTitle, color = Ds.primaryText.value) }
                ListRow(Modifier.testTag("privacy.policy"), divider = false, onClick = { router.push(AppRoute.PrivacyPolicy) }) {
                    SettingsRowLabel(L10n.System.privacyPolicy, symbol = "doc.text")
                }
            }
            ListSection {
                ListRow(Modifier.testTag("privacy.erase"), divider = false, onClick = { isErasing = true }) { Text(L10n.System.eraseEverything, style = DsType.rowTitle, color = Ds.record.value) }
            }
        }
    }
    if (isErasing) EraseSheet(controller, lock) { isErasing = false }
}

/** Nothing comes back after this, so it asks for more than a tap. */
@Composable
private fun EraseSheet(controller: SystemController, lock: AppLockController, onDismiss: () -> Unit) {
    val router = LocalRouter.current
    val scope = rememberCoroutineScope()
    var typed by remember { mutableStateOf("") }
    var failed by remember { mutableStateOf(false) }
    val isConfirmed = typed.trim().equals(L10n.System.eraseWord, ignoreCase = true)
    IosSheet(onDismiss) {
        SheetBar(L10n.System.eraseEverything, leading = { TextAction(L10n.Common.cancel, color = Ds.primaryText.value, onClick = onDismiss) })
        SheetBody(Modifier.padding(top = Spacing.medium)) {
            FormSection {
                FormRow { Text(L10n.System.eraseWarning, style = DsType.rowTitle, color = Ds.primaryText.value) }
                FormTextField(typed, { typed = it.uppercase() }, L10n.System.eraseInstruction(L10n.System.eraseWord), Modifier.testTag("erase.confirm"), divider = false)
            }
            FormSection {
                FormButton(L10n.System.eraseEverything, Modifier.testTag("erase.run"), destructive = true, enabled = isConfirmed && !controller.isErasing, divider = controller.isErasing || failed) {
                    scope.launch {
                        if (controller.eraseEverything()) {
                            lock.forgetLock()
                            onDismiss()
                            router.select(Destination.HOME)
                        } else {
                            failed = true
                        }
                    }
                }
                if (controller.isErasing) FormRow(divider = failed) { ProgressRing(null) }
                if (failed) FormRow(divider = false) { Text(L10n.System.errorRecording, style = DsType.rowTitle, color = Ds.record.value) }
            }
        }
    }
}

// MARK: - Calendars

/** Which calendars the app reads, as CalendarsModel.swift. Home picks up a change the next time it loads. */
class CalendarsModel(private val provider: CalendarProvider, private val choices: CalendarChoices) {
    data class Account(val id: String, val name: String, val calendars: List<CalendarSource>)

    var access by mutableStateOf(provider.access)
        private set
    /** Null until the first load, so the screen does not flash "No calendars" while it asks. */
    var accounts by mutableStateOf<List<Account>?>(null)
        private set
    var hidden by mutableStateOf(choices.hidden)
        private set

    val isUsing: Boolean get() = access == CalendarAccess.GRANTED

    suspend fun load() {
        access = provider.access
        hidden = choices.hidden
        accounts = provider.calendars().groupBy { it.accountID }.map { (id, calendars) ->
            Account(id, calendars.firstOrNull()?.account ?: "", calendars.sortedWith { a, b -> localizedStandardCompare(a.title, b.title) })
        }.sortedWith { a, b -> localizedStandardCompare(a.name, b.name) }
    }

    /** On asks when it has not been asked yet. Off stops reading at once, and the system keeps its permission. */
    suspend fun setUsing(isOn: Boolean) {
        if (isOn) {
            provider.requestAccess()
        } else {
            choices.isOn = false
            // Turned off on purpose: Home should not offer Connect again.
            choices.isConnectHidden = true
        }
        load()
    }

    fun isShown(calendar: CalendarSource): Boolean = calendar.id !in hidden

    fun setShown(isShown: Boolean, calendar: CalendarSource) {
        choices.setShown(isShown, calendar.id)
        hidden = choices.hidden
    }
}

@Composable
fun CalendarsScreen(model: CalendarsModel) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    LaunchedEffect(Unit) { model.load() }
    Screen(title = L10n.Calendars.title, modifier = Modifier.testTag("screen.calendars")) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding())) {
            ListSection(footer = if (model.isUsing) L10n.Calendars.revoke else L10n.Calendars.useNote) {
                ListToggle(L10n.Calendars.use, model.isUsing, { value -> scope.launch { model.setUsing(value) } }, Modifier.testTag("calendars.use"), divider = false)
            }
            if (model.access == CalendarAccess.DENIED) {
                ListSection {
                    ListRow { Text(L10n.Calendars.denied, style = DsType.rowTitle, color = Ds.primaryText.value) }
                    ListRow(Modifier.testTag("calendars.openSettings"), divider = false, onClick = { openAppSettings(context) }) { Text(L10n.Calendars.openSettings, style = DsType.rowTitle, color = Ds.action.value) }
                }
            }
            if (model.isUsing) {
                if (model.accounts?.isEmpty() == true) ListRow(divider = false) { Text(L10n.Calendars.none, style = DsType.rowTitle, color = Ds.secondaryText.value) }
                for (account in model.accounts ?: emptyList()) {
                    ListSection(account.name) {
                        account.calendars.forEachIndexed { index, calendar ->
                            ListRow(Modifier.testTag("calendars.item.${calendar.id}"), divider = index < account.calendars.lastIndex, onClick = { model.setShown(!model.isShown(calendar), calendar) }) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    val tint = calendar.tint?.let { Color(it.red.toFloat(), it.green.toFloat(), it.blue.toFloat()) } ?: Ds.secondaryText.value
                                    Box(Modifier.size(12.dp).clip(CircleShape).background(tint))
                                    Spacer(Modifier.width(Spacing.small))
                                    Text(calendar.title, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f))
                                    com.meetlaud.app.designsystem.IosSwitch(model.isShown(calendar), { model.setShown(it, calendar) })
                                }
                            }
                        }
                    }
                }
                ListSection(L10n.Calendars.addTitle) { ListRow(divider = false) { Text(L10n.Calendars.addHelp, style = DsType.meta, color = Ds.secondaryText.value) } }
            }
        }
    }
}

// MARK: - Storage

@Composable
fun StorageBackupScreen(controller: SystemController) {
    val scope = rememberCoroutineScope()
    var isExporting by remember { mutableStateOf(false) }
    var isRestoring by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { controller.refreshUsage() }
    Screen(title = L10n.System.storageTitle, modifier = Modifier.testTag("screen.storage")) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding())) {
            ListSection(L10n.System.usage) {
                val usage = controller.usage
                if (usage != null) {
                    ListRow(Modifier.testTag("storage.usage")) {
                        Column(verticalArrangement = Arrangement.spacedBy(Spacing.compact), modifier = Modifier.padding(vertical = Spacing.small)) {
                            Text(L10n.System.usageInUse(usage.total.fileSize), style = DsType.heading, color = Ds.primaryText.value)
                            val parts = listOf(
                                UsagePart("recordings", L10n.System.usageRecordings, usage.recordings, usage.recordings.fileSize),
                                UsagePart("models", L10n.System.usageModels, usage.models, usage.models.fileSize),
                                UsagePart("library", L10n.System.usageLibrary, usage.library, usage.library.fileSize),
                                UsagePart("cache", L10n.System.usageCache, usage.cache, usage.cache.fileSize),
                            )
                            // The whole bar is the app's share next to what is free, so "how full" is visible.
                            UsageBar(parts, total = usage.available?.let { usage.total + it })
                            usage.available?.let { available ->
                                Row { Text(L10n.System.usageFree, style = DsType.meta, color = Ds.secondaryText.value, modifier = Modifier.weight(1f)); Text(available.fileSize, style = DsType.meta, color = Ds.secondaryText.value) }
                            }
                        }
                    }
                    ListRow(Modifier.testTag("storage.clearCache"), divider = false, onClick = { scope.launch { controller.clearCache() } }) { Text(L10n.System.clearCache, style = DsType.rowTitle, color = Ds.primaryText.value) }
                } else {
                    // Measuring a large library takes a moment. The bar stays in place, moving.
                    ListRow(divider = false) { ActivityBar(null, Modifier.padding(vertical = Spacing.medium)) }
                }
            }
            ListSection(L10n.System.backup) {
                ListToggle(PlatformText.deviceBackup, controller.isBackupIncluded, controller::changeBackupIncluded, Modifier.testTag("storage.backup"))
                ListRow(divider = false) { Text(PlatformText.deviceBackupNote, style = DsType.meta, color = Ds.secondaryText.value) }
            }
            ListSection(L10n.System.moveLibrary) {
                ListRow(Modifier.testTag("storage.export"), onClick = { isExporting = true }) { Text(L10n.System.exportLibrary, style = DsType.rowTitle, color = Ds.primaryText.value) }
                ListRow(Modifier.testTag("storage.import"), onClick = { isRestoring = true }) { Text(L10n.System.importLibrary, style = DsType.rowTitle, color = Ds.primaryText.value) }
                ListRow(divider = false) { Text(L10n.System.moveLibraryNote, style = DsType.meta, color = Ds.secondaryText.value) }
            }
        }
    }
    if (isExporting) ExportLibrarySheet(controller) { isExporting = false; controller.resetArchive() }
    if (isRestoring) RestoreLibrarySheet(controller) { isRestoring = false; controller.resetArchive() }
}

@Composable
private fun ArchiveStatus(outcome: SystemController.ArchiveOutcome) {
    when (outcome) {
        is SystemController.ArchiveOutcome.Working -> FormRow(Modifier.testTag("archive.progress"), divider = false) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.compact)) {
                ActivityBar(outcome.fraction, Modifier.weight(1f))
                Text(percent(outcome.fraction), style = DsType.meta.copy(fontFeatureSettings = "tnum"), color = Ds.primaryText.value)
            }
        }
        is SystemController.ArchiveOutcome.Failed -> FormRow(Modifier.testTag("archive.error"), divider = false) {
            Text(
                when (outcome.reason) {
                    SystemController.Reason.RECORDING -> L10n.System.errorRecording
                    SystemController.Reason.WRONG_PASSWORD -> L10n.System.errorPassword
                    SystemController.Reason.DAMAGED -> L10n.System.errorDamaged
                    SystemController.Reason.INCOMPATIBLE -> L10n.System.errorIncompatible
                    SystemController.Reason.OTHER -> L10n.System.errorOther
                },
                style = DsType.rowTitle, color = Ds.record.value,
            )
        }
        SystemController.ArchiveOutcome.Restored -> FormRow(Modifier.testTag("archive.restored"), divider = false) { Text(L10n.System.restoreDone, style = DsType.rowTitle, color = Ds.primaryText.value) }
        else -> Unit
    }
}

@Composable
private fun PasswordField(value: String, onValue: (String) -> Unit, placeholder: String, tag: String, divider: Boolean = true) {
    FormRow(Modifier.testTag(tag), divider) {
        Box(Modifier.fillMaxWidth()) {
            if (value.isEmpty()) Text(placeholder, style = DsType.rowTitle, color = Ds.secondaryText.value)
            androidx.compose.foundation.text.BasicTextField(
                value, onValue, Modifier.fillMaxWidth(), singleLine = true,
                textStyle = DsType.rowTitle.copy(color = Ds.primaryText.value),
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                cursorBrush = androidx.compose.ui.graphics.SolidColor(Ds.action.value),
            )
        }
    }
}

@Composable
private fun ExportLibrarySheet(controller: SystemController, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var password by remember { mutableStateOf("") }
    var repeated by remember { mutableStateOf("") }
    var includesVoicePrints by remember { mutableStateOf(false) }
    val minimum = 8
    val isValid = password.length >= minimum && password == repeated
    val isWorking = controller.archive is SystemController.ArchiveOutcome.Working
    IosSheet({ if (!isWorking) onDismiss() }) {
        SheetBar(L10n.System.exportLibrary, leading = { TextAction(L10n.Common.done, color = Ds.primaryText.value, enabled = !isWorking, onClick = onDismiss) })
        SheetBody(Modifier.padding(top = Spacing.medium)) {
            FormSection(footer = L10n.System.passwordNote(minimum)) {
                PasswordField(password, { password = it }, L10n.System.password, "archive.password")
                PasswordField(repeated, { repeated = it }, L10n.System.passwordRepeat, "archive.passwordRepeat", divider = false)
            }
            FormSection(footer = L10n.System.includeVoicePrintsNote) {
                FormToggle(L10n.System.includeVoicePrints, includesVoicePrints, { includesVoicePrints = it }, divider = false)
            }
            FormSection {
                val outcome = controller.archive
                if (outcome is SystemController.ArchiveOutcome.Exported) {
                    FormButton(L10n.System.saveFile, Modifier.testTag("archive.share"), symbol = "square.and.arrow.up", divider = false) {
                        com.meetlaud.app.feature.shared.Sharing.shareFile(context, outcome.file, "application/octet-stream")
                    }
                } else {
                    FormButton(L10n.System.createFile, Modifier.testTag("archive.create"), enabled = isValid && !isWorking, divider = outcome !is SystemController.ArchiveOutcome.Idle) {
                        scope.launch { controller.exportLibrary(password, includesVoicePrints) }
                    }
                }
                ArchiveStatus(outcome)
            }
        }
    }
}

@Composable
private fun RestoreLibrarySheet(controller: SystemController, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var file by remember { mutableStateOf<File?>(null) }
    var fileName by remember { mutableStateOf<String?>(null) }
    var password by remember { mutableStateOf("") }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            // A content address, not a path: the archive is copied in first, and removed when the sheet closes.
            val copy = File(context.cacheDir, "restore.meetlaudbackup")
            runCatching { context.contentResolver.openInputStream(uri)!!.use { input -> copy.outputStream().use { input.copyTo(it) } } }
                .onSuccess { file = copy; fileName = uri.lastPathSegment?.substringAfterLast('/') }
        }
    }
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { file?.delete() } }
    IosSheet(onDismiss) {
        SheetBar(L10n.System.importLibrary, leading = { TextAction(L10n.Common.done, color = Ds.primaryText.value, onClick = onDismiss) })
        SheetBody(Modifier.padding(top = Spacing.medium)) {
            FormSection(footer = L10n.System.restoreWarning) {
                FormButton(fileName ?: L10n.System.chooseFile, Modifier.testTag("archive.choose")) { picker.launch(arrayOf("*/*")) }
                PasswordField(password, { password = it }, L10n.System.password, "archive.password", divider = false)
            }
            FormSection {
                FormButton(L10n.System.restore, Modifier.testTag("archive.restore"), destructive = true, enabled = file != null && password.isNotEmpty(), divider = controller.archive !is SystemController.ArchiveOutcome.Idle) {
                    file?.let { chosen -> scope.launch { controller.restoreLibrary(chosen, password) } }
                }
                ArchiveStatus(controller.archive)
            }
        }
    }
}

// MARK: - Vocabulary

/** Names and terms the transcript should spell a certain way, as VocabularyView.swift. */
@Composable
fun VocabularyScreen(folders: List<Folder>) {
    val defaults = LocalPreferences.current
    var entries by remember { mutableStateOf(VocabularyPreferences.load(defaults)) }
    var editing by remember { mutableStateOf<VocabularyEntry?>(null) }
    fun save(entry: VocabularyEntry) {
        val index = entries.indexOfFirst { it.id == entry.id }
        entries = if (index >= 0) entries.toMutableList().also { it[index] = entry } else entries + entry
        VocabularyPreferences.save(entries, defaults)
    }
    fun delete(entry: VocabularyEntry) {
        entries = entries.filter { it.id != entry.id }
        VocabularyPreferences.save(entries, defaults)
    }
    // Words for every recording first, then each folder in the order of the library.
    val known = folders.map { it.id }.toSet()
    val groups = buildList<Pair<FolderID?, List<VocabularyEntry>>> {
        // A word whose folder was deleted keeps working everywhere, rather than vanishing.
        val global = entries.filter { entry -> entry.folderID?.let { it !in known } ?: true }
        if (global.isNotEmpty()) add(null to global)
        for (folder in folders) entries.filter { it.folderID == folder.id }.takeIf { it.isNotEmpty() }?.let { add(folder.id to it) }
    }
    Screen(
        title = L10n.Vocabulary.title,
        modifier = Modifier.testTag("screen.vocabulary"),
        trailing = { GlassCircleButton("plus", L10n.Vocabulary.add, Modifier.testTag("vocabulary.add")) { editing = VocabularyEntry(heard = "", written = "") } },
    ) {
        if (entries.isEmpty()) {
            EmptyState(L10n.Vocabulary.title, L10n.Vocabulary.hint, "character.book.closed")
        } else {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(contentPadding())) {
                groups.forEachIndexed { index, (folder, list) ->
                    val header = if (groups.size > 1 || folder != null) folder?.let { id -> folders.firstOrNull { it.id == id }?.name } ?: L10n.Vocabulary.everywhere else null
                    ListSection(header, if (index == groups.lastIndex) L10n.Vocabulary.hint else null) {
                        list.forEachIndexed { row, entry ->
                            SwipeRow(trailing = listOf(SwipeAction(L10n.Library.delete, "trash", Ds.record.value) { delete(entry) })) {
                                ListRow(divider = row < list.lastIndex, onClick = { editing = entry }) { RowLabel(entry.written, entry.heard) }
                            }
                        }
                    }
                }
            }
        }
    }
    editing?.let { entry -> VocabularyEditor(entry, folders, ::save) { editing = null } }
}

@Composable
private fun VocabularyEditor(initial: VocabularyEntry, folders: List<Folder>, onSave: (VocabularyEntry) -> Unit, onDismiss: () -> Unit) {
    var entry by remember { mutableStateOf(initial) }
    var folderMenu by remember { mutableStateOf(false) }
    IosSheet(onDismiss, large = false) {
        SheetBar(
            L10n.Vocabulary.add,
            leading = { TextAction(L10n.Common.cancel, color = Ds.primaryText.value, onClick = onDismiss) },
            trailing = { TextAction(L10n.Common.save, Modifier.testTag("vocabulary.save"), enabled = entry.isValid, style = DsType.heading) { onSave(entry); onDismiss() } },
        )
        SheetBody(Modifier.padding(top = Spacing.medium)) {
            FormSection {
                FormTextField(entry.heard, { entry = entry.copy(heard = it) }, L10n.Vocabulary.heard, Modifier.testTag("vocabulary.heard"))
                FormTextField(entry.written, { entry = entry.copy(written = it) }, L10n.Vocabulary.written, Modifier.testTag("vocabulary.written"), divider = folders.isNotEmpty())
                if (folders.isNotEmpty()) {
                    FormRow(Modifier.testTag("vocabulary.folder"), divider = false, onClick = { folderMenu = true }) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(L10n.Vocabulary.appliesTo, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f))
                            Box {
                                Text(entry.folderID?.let { id -> folders.firstOrNull { it.id == id }?.name } ?: L10n.Vocabulary.everywhere, style = DsType.rowTitle, color = Ds.secondaryText.value)
                                IosMenu(folderMenu, { folderMenu = false }, listOf(MenuAction(L10n.Vocabulary.everywhere, isChecked = entry.folderID == null) { entry = entry.copy(folderID = null) }) +
                                    folders.map { folder -> MenuAction(folder.name, isChecked = entry.folderID == folder.id) { entry = entry.copy(folderID = folder.id) } })
                            }
                        }
                    }
                }
            }
        }
    }
}

