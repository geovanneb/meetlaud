package com.meetlaud.app.feature.tools

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.graphics.asImageBitmap
import com.meetlaud.app.designsystem.AlertButton
import com.meetlaud.app.designsystem.ControlSize
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.EmptyState
import com.meetlaud.app.designsystem.FormButton
import com.meetlaud.app.designsystem.FormRow
import com.meetlaud.app.designsystem.FormSection
import com.meetlaud.app.designsystem.FormTextField
import com.meetlaud.app.designsystem.GlassCircleButton
import com.meetlaud.app.designsystem.IconSize
import com.meetlaud.app.designsystem.IosAlert
import com.meetlaud.app.designsystem.IosMenu
import com.meetlaud.app.designsystem.IosSheet
import com.meetlaud.app.designsystem.MenuAction
import com.meetlaud.app.designsystem.PlainButton
import com.meetlaud.app.designsystem.PrimaryAction
import com.meetlaud.app.designsystem.ProgressRing
import com.meetlaud.app.designsystem.Radius
import com.meetlaud.app.designsystem.RowDivider
import com.meetlaud.app.designsystem.RowLabel
import com.meetlaud.app.designsystem.SearchField
import com.meetlaud.app.designsystem.SecondaryAction
import com.meetlaud.app.designsystem.SegmentedControl
import com.meetlaud.app.designsystem.SfIcon
import com.meetlaud.app.designsystem.SheetBar
import com.meetlaud.app.designsystem.SheetBody
import com.meetlaud.app.designsystem.SheetHeader
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.designsystem.SwipeAction
import com.meetlaud.app.designsystem.SwipeRow
import com.meetlaud.app.designsystem.TapTarget
import com.meetlaud.app.designsystem.TextAction
import com.meetlaud.app.feature.shared.SkillLibrary
import com.meetlaud.app.feature.shared.SummaryCenter
import com.meetlaud.app.feature.shared.Sharing
import com.meetlaud.app.feature.shared.TranscribeOutcome
import com.meetlaud.app.feature.shared.displayName
import com.meetlaud.app.feature.shared.displaySummary
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.localization.category
import com.meetlaud.app.localization.sectionTitle
import com.meetlaud.app.localization.templateName
import com.meetlaud.app.routing.AppRoute
import com.meetlaud.app.routing.LocalRouter
import com.meetlaud.app.shell.Screen
import com.meetlaud.connectors.ConnectorContent
import com.meetlaud.connectors.ConnectorIcon
import com.meetlaud.connectors.ConnectorManifest
import com.meetlaud.connectors.ConnectorRegistry
import com.meetlaud.domain.BuiltInSkills
import com.meetlaud.domain.BuiltInTemplates
import com.meetlaud.domain.Recording
import com.meetlaud.domain.SectionKind
import com.meetlaud.domain.Skill
import com.meetlaud.domain.SkillCodec
import com.meetlaud.domain.SummaryTemplate
import com.meetlaud.domain.TemplateCategory
import com.meetlaud.domain.TemplateCodec
import com.meetlaud.domain.TemplateSection
import com.meetlaud.domain.caseInsensitiveContains
import kotlinx.coroutines.launch
import java.io.File

/** Settings a connector brings for itself, shown in a sheet from Tools. */
fun interface ConnectorSettings {
    @Composable
    fun Content(onDone: () -> Unit)
}

private enum class ToolsTab { SKILLS, TEMPLATES, CONNECTORS }

/** Skills, templates, and connectors, one tab each, as ToolsView.swift. */
@Composable
fun ToolsScreen(
    center: SummaryCenter,
    skills: SkillLibrary,
    connectors: ConnectorRegistry,
    connectorSettings: (String) -> ConnectorSettings?,
    recordings: suspend () -> List<Recording>,
) {
    var tab by rememberSaveable { mutableStateOf(ToolsTab.SKILLS) }
    var addOpen by remember { mutableStateOf(false) }
    var editingSkill by remember { mutableStateOf<Skill?>(null) }
    var editingTemplate by remember { mutableStateOf<SummaryTemplate?>(null) }
    var isDrafting by remember { mutableStateOf(false) }
    var importFailed by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        scope.launch {
            val data = runCatching { context.contentResolver.openInputStream(uri)!!.use { it.readBytes() } }.getOrNull()
            val ok = data != null && runCatching {
                if (tab == ToolsTab.SKILLS) skills.save(SkillCodec.decode(data)) else center.importTemplate(data)
            }.isSuccess
            if (!ok) importFailed = true
        }
    }

    Screen(
        title = L10n.Nav.tools,
        modifier = Modifier.testTag("screen.tools"),
        trailing = {
            if (tab != ToolsTab.CONNECTORS) {
                Box {
                    GlassCircleButton("plus", L10n.Home.add, Modifier.testTag(if (tab == ToolsTab.SKILLS) "skills.add" else "templates.add")) { addOpen = true }
                    val actions = if (tab == ToolsTab.SKILLS) {
                        listOf(
                            MenuAction(L10n.Skills.new, "square.and.pencil", tag = "skills.new") { editingSkill = Skill(name = "", summary = "", instructions = "") },
                            MenuAction(L10n.Templates.importFile, "square.and.arrow.down") { importer.launch(arrayOf("application/json")) },
                        )
                    } else {
                        listOf(
                            MenuAction(L10n.Templates.new, "square.and.pencil", tag = "templates.new") { editingTemplate = blankTemplate() },
                            MenuAction(L10n.Templates.createWithAI, "sparkles", tag = "templates.ai") { isDrafting = true },
                            MenuAction(L10n.Templates.importFile, "square.and.arrow.down") { importer.launch(arrayOf("application/json")) },
                        )
                    }
                    IosMenu(addOpen, { addOpen = false }, actions)
                }
            }
        },
    ) {
        SegmentedControl(
            listOf(L10n.Tools.skills, L10n.Tools.templates, L10n.Tools.connectors), tab.ordinal, { tab = ToolsTab.entries[it] },
            Modifier.padding(horizontal = Spacing.medium, vertical = Spacing.small).testTag("tools.tabs"),
        )
        Box(Modifier.weight(1f)) {
            when (tab) {
                ToolsTab.SKILLS -> SkillsTab(skills) { editingSkill = it }
                ToolsTab.TEMPLATES -> TemplatesTab(center)
                ToolsTab.CONNECTORS -> ConnectorsTab(connectors, connectorSettings)
            }
        }
    }
    editingSkill?.let { skill -> SkillEditor(skill, onSave = skills::save) { editingSkill = null } }
    editingTemplate?.let { template -> TemplateEditor(template, onSave = { scope.launch { center.save(it) } }) { editingTemplate = null } }
    if (isDrafting) TemplateDraftSheet(center, onDraft = { editingTemplate = it }) { isDrafting = false }
    if (importFailed) IosAlert(L10n.Templates.importFailed, null, listOf(AlertButton(L10n.Common.ok)), onDismiss = { importFailed = false })
}

fun blankTemplate() = SummaryTemplate(name = "", category = TemplateCategory.GENERAL, instructions = "", sections = listOf(TemplateSection("")))

// MARK: - Skills

/** Saved ways of answering. "Use" starts a chat that follows the skill. */
@Composable
private fun SkillsTab(library: SkillLibrary, onEdit: (Skill) -> Unit) {
    val router = LocalRouter.current
    @Composable
    fun Row(skill: Skill) {
        Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.medium, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.medium)) {
            RowLabel(skill.displayName, skill.displaySummary, Modifier.weight(1f), titleLines = 2)
            SecondaryAction(L10n.Skills.use, Modifier.testTag("skill.use"), ControlSize.SMALL) { router.push(AppRoute.AskSkill(skill.id)) }
        }
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = com.meetlaud.app.shell.contentPadding(top = Spacing.small)) {
        item("mine.header") { SectionTitle(L10n.Skills.mine) }
        if (library.mine.isEmpty()) item("mine.empty") { Text(L10n.Skills.mineEmpty, style = DsType.meta, color = Ds.secondaryText.value, modifier = Modifier.padding(horizontal = Spacing.medium, vertical = Spacing.small)) }
        items(library.mine, key = { it.id }) { skill ->
            SwipeRow(trailing = listOf(SwipeAction(L10n.Library.delete, "trash", Ds.record.value) { library.delete(skill) })) {
                PlainButton({ onEdit(skill) }, Modifier.fillMaxWidth()) { Row(skill) }
            }
            RowDivider(Modifier.padding(horizontal = Spacing.medium))
        }
        item("official.header") { SectionTitle(L10n.Skills.official, Modifier.padding(top = Spacing.medium)) }
        items(BuiltInSkills.all, key = { it.id }) { skill ->
            Row(skill)
            RowDivider(Modifier.padding(horizontal = Spacing.medium))
        }
    }
}

@Composable
private fun SectionTitle(title: String, modifier: Modifier = Modifier) {
    Text(title, style = DsType.meta, color = Ds.secondaryText.value, modifier = modifier.padding(horizontal = Spacing.medium, vertical = Spacing.small).semantics { heading() })
}

@Composable
private fun SkillEditor(initial: Skill, onSave: (Skill) -> Unit, onDismiss: () -> Unit) {
    var skill by remember { mutableStateOf(initial) }
    IosSheet(onDismiss) {
        SheetBar(
            if (skill.name.isEmpty()) L10n.Skills.new else L10n.Skills.edit,
            leading = { TextAction(L10n.Common.cancel, color = Ds.primaryText.value, onClick = onDismiss) },
            trailing = { TextAction(L10n.Common.save, Modifier.testTag("skill.save"), enabled = skill.isValid, style = DsType.heading) { onSave(skill); onDismiss() } },
        )
        SheetBody(Modifier.padding(top = Spacing.medium)) {
            FormSection {
                FormTextField(skill.name, { skill = skill.copy(name = it) }, L10n.Skills.name, Modifier.testTag("skill.name"))
                FormTextField(skill.summary, { skill = skill.copy(summary = it) }, L10n.Skills.summary, divider = false, singleLine = false)
            }
            FormSection(footer = L10n.Skills.instructionsNote) {
                FormTextField(
                    skill.instructions, { skill = skill.copy(instructions = it.take(Skill.INSTRUCTIONS_LIMIT)) }, L10n.Skills.instructions,
                    Modifier.testTag("skill.instructions").heightIn(min = 140.dp), divider = false, singleLine = false,
                )
            }
        }
    }
}

// MARK: - Templates

val TemplateCategory.symbol: String
    get() = when (this) {
        TemplateCategory.GENERAL -> "square.grid.2x2"
        TemplateCategory.MEETING -> "person.3"
        TemplateCategory.SPEECH -> "megaphone"
        TemplateCategory.INTERVIEW -> "person.text.rectangle"
        TemplateCategory.CALL -> "phone"
    }

val TemplateCategory.tintIndex: Int get() = TemplateCategory.entries.indexOf(this)

val TemplateCategory.title: String get() = L10n.Templates.category(raw)

val SummaryTemplate.symbol: String
    get() = when (id) {
        BuiltInTemplates.DEFAULT_ID -> "sparkles"
        "builtin.minutes" -> "list.clipboard"
        "builtin.discussion" -> "bubble.left.and.bubble.right"
        "builtin.oneonone" -> "person.2"
        "builtin.lecture" -> "graduationcap"
        "builtin.interview" -> "person.text.rectangle"
        "builtin.call" -> "phone"
        else -> category.symbol
    }

/** What the summary will hold, in the person's language: the section titles. */
val SummaryTemplate.outline: String get() = sections.map { L10n.Summary.sectionTitle(it.title) }.filter { it.isNotEmpty() }.joinToString(" · ")

/** The template library: categories first, then a row of cards per category, as TemplatesTab.swift. */
@Composable
private fun TemplatesTab(center: SummaryCenter) {
    val router = LocalRouter.current
    var query by rememberSaveable { mutableStateOf("") }
    LaunchedEffect(Unit) { center.reloadTemplates() }
    fun matches(template: SummaryTemplate) = query.isEmpty() || L10n.Summary.templateName(template.name).caseInsensitiveContains(query)
    val mine = center.userTemplates.filter(::matches)
    fun builtIn(category: TemplateCategory) = BuiltInTemplates.all.filter { it.category == category && matches(it) }
    val results = mine + TemplateCategory.entries.flatMap(::builtIn)
    val screenWidth = LocalConfiguration.current.screenWidthDp.dp

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = 96.dp), verticalArrangement = Arrangement.spacedBy(Spacing.large)) {
            if (query.isEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.compact)) {
                    Text(L10n.Templates.categories, style = DsType.sectionTitle, color = Ds.primaryText.value, modifier = Modifier.padding(horizontal = Spacing.medium).semantics { heading() })
                    // Two rows that scroll sideways, each row as tall as its tallest tile.
                    val all = TemplateCategory.entries
                    val half = (all.size + 1) / 2
                    Column(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Spacing.medium), verticalArrangement = Arrangement.spacedBy(Spacing.compact)) {
                        for (row in listOf(all.take(half), all.drop(half))) {
                            Row(Modifier.height(IntrinsicSize.Max), horizontalArrangement = Arrangement.spacedBy(Spacing.compact)) {
                                for (category in row) {
                                    PlainButton({ router.push(AppRoute.TemplateCategory(category.raw)) }, Modifier.width(minOf(170.dp, screenWidth * 0.42f)).fillMaxHeight().testTag("templates.category.${category.raw}")) {
                                        Column(Modifier.fillMaxSize().clip(RoundedCornerShape(Radius.medium)).background(Ds.surface.value).padding(Spacing.medium), verticalArrangement = Arrangement.spacedBy(Spacing.small)) {
                                            SfIcon(category.symbol, tint = Ds.accents[category.tintIndex % Ds.accents.size].value, size = IconSize.icon)
                                            Text(category.title, style = DsType.rowTitle, color = Ds.primaryText.value)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if (mine.isNotEmpty()) {
                    Column(verticalArrangement = Arrangement.spacedBy(Spacing.compact)) {
                        Text(L10n.Templates.mine, style = DsType.sectionTitle, color = Ds.primaryText.value, modifier = Modifier.padding(horizontal = Spacing.medium).semantics { heading() })
                        CardRow(mine, center, screenWidth)
                    }
                }
                for (category in TemplateCategory.entries) {
                    val templates = builtIn(category)
                    if (templates.isEmpty()) continue
                    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
                        PlainButton({ router.push(AppRoute.TemplateCategory(category.raw)) }, Modifier.padding(horizontal = Spacing.medium).heightIn(min = TapTarget).semantics { heading() }.testTag("templates.section.${category.raw}")) {
                            SfIcon(category.symbol, tint = Ds.accents[category.tintIndex % Ds.accents.size].value, size = DsType.heading.fontSize)
                            Spacer(Modifier.width(Spacing.small))
                            Text(category.title, style = DsType.sectionTitle, color = Ds.primaryText.value)
                            Spacer(Modifier.width(Spacing.small))
                            SfIcon("chevron.right", tint = Ds.secondaryText.value, size = DsType.note.fontSize)
                        }
                        CardRow(templates, center, screenWidth)
                    }
                }
            } else {
                TemplateGrid(results, center, Modifier.padding(horizontal = Spacing.medium))
            }
        }
        if (results.isEmpty()) EmptyState(L10n.Library.noResults, "", "magnifyingglass")
        Box(Modifier.align(Alignment.BottomCenter).navigationBarsPadding().imePadding().padding(horizontal = Spacing.medium).padding(bottom = Spacing.small)) {
            SearchField(query, { query = it }, L10n.Templates.search, focus = false)
        }
    }
}

/** A row of cards that scrolls sideways, with the next card peeking in. */
@Composable
private fun CardRow(templates: List<SummaryTemplate>, center: SummaryCenter, screenWidth: androidx.compose.ui.unit.Dp) {
    Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Spacing.medium).height(IntrinsicSize.Max), horizontalArrangement = Arrangement.spacedBy(Spacing.compact)) {
        for (template in templates) TemplateCard(template, center, Modifier.width(minOf(220.dp, screenWidth * 0.8f)).fillMaxHeight())
    }
}

/** Cards that wrap into as many columns as fit. */
@Composable
private fun TemplateGrid(templates: List<SummaryTemplate>, center: SummaryCenter, modifier: Modifier = Modifier) {
    val width = LocalConfiguration.current.screenWidthDp.dp - Spacing.medium * 2
    val columns = maxOf(1, ((width + Spacing.compact) / (160.dp + Spacing.compact)).toInt())
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.compact)) {
        for (row in templates.chunked(columns)) {
            Row(Modifier.height(IntrinsicSize.Max), horizontalArrangement = Arrangement.spacedBy(Spacing.compact)) {
                for (template in row) TemplateCard(template, center, Modifier.weight(1f).fillMaxHeight())
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/** One template: its mark, its name, what it holds, and whether it is the default. */
@Composable
private fun TemplateCard(template: SummaryTemplate, center: SummaryCenter, modifier: Modifier) {
    val router = LocalRouter.current
    val isDefault = template.id == center.defaultTemplateID
    PlainButton({ router.push(AppRoute.Template(template.id)) }, modifier.testTag("template.card")) {
        Column(
            Modifier.fillMaxSize().clip(RoundedCornerShape(Radius.medium)).background(Ds.surface.value)
                .border(1.dp, Ds.selection.value, RoundedCornerShape(Radius.medium)).padding(Spacing.medium),
            verticalArrangement = Arrangement.spacedBy(Spacing.small),
        ) {
            SfIcon(template.symbol, Modifier.padding(bottom = Spacing.xSmall), tint = Ds.accents[template.category.tintIndex % Ds.accents.size].value, size = IconSize.iconLarge)
            Text(L10n.Summary.templateName(template.name), style = DsType.heading, color = Ds.primaryText.value)
            if (template.outline.isNotEmpty()) Text(template.outline, style = DsType.meta, color = Ds.secondaryText.value)
            Spacer(Modifier.weight(1f).heightIn(min = Spacing.small))
            if (isDefault) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.xSmall)) {
                    SfIcon("star.fill", tint = Ds.action.value, size = DsType.badge.fontSize)
                    Text(L10n.Templates.isDefault, style = DsType.badge, color = Ds.action.value)
                }
            } else {
                Text(if (template.isBuiltIn) L10n.Templates.builtIn else template.category.title, style = DsType.badge, color = Ds.secondaryText.value)
            }
        }
    }
}

/** Every template in one category, as a grid of cards. */
@Composable
fun CategoryTemplatesScreen(category: TemplateCategory, center: SummaryCenter) {
    Screen(title = category.title, modifier = Modifier.testTag("screen.templateCategory")) {
        val templates = center.userTemplates.filter { it.category == category } + BuiltInTemplates.all.filter { it.category == category }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = Spacing.medium, bottom = Spacing.large)) {
            TemplateGrid(templates, center, Modifier.padding(horizontal = Spacing.medium))
        }
    }
}

/** One template, with what it holds and where to try it, as TemplateDetailView. */
@Composable
fun TemplateDetailScreen(templateID: String, center: SummaryCenter, recordings: suspend () -> List<Recording>) {
    val router = LocalRouter.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val template = center.templates.firstOrNull { it.id == templateID } ?: return
    var transcribed by remember { mutableStateOf<List<Recording>>(emptyList()) }
    var editing by remember { mutableStateOf<SummaryTemplate?>(null) }
    var isConfirmingDelete by remember { mutableStateOf(false) }
    LaunchedEffect(templateID) { transcribed = recordings() }
    Screen(
        title = L10n.Summary.templateName(template.name),
        modifier = Modifier.testTag("screen.template"),
        trailing = {
            var open by remember { mutableStateOf(false) }
            Box {
                GlassCircleButton("ellipsis", L10n.Library.more, Modifier.testTag("template.more")) { open = true }
                val actions = mutableListOf(MenuAction(L10n.Templates.setDefault, "star", isEnabled = center.defaultTemplateID != template.id, tag = "template.default") { center.setDefault(template) })
                if (!template.isBuiltIn) actions += MenuAction(L10n.Templates.edit, "pencil") { editing = template }
                actions += MenuAction(L10n.Templates.duplicate, "plus.square.on.square", tag = "template.duplicate") {
                    editing = SummaryTemplate(name = L10n.Templates.copyName(L10n.Summary.templateName(template.name)), category = template.category, instructions = template.instructions, sections = template.sections)
                }
                actions += MenuAction(L10n.Summary.share, "square.and.arrow.up") {
                    val file = File(Sharing.exportFolder(context), "${template.name.ifBlank { "Template" }}.json").apply { writeBytes(TemplateCodec.encode(template)) }
                    Sharing.shareFile(context, file, "application/json")
                }
                if (!template.isBuiltIn) actions += MenuAction(L10n.Library.delete, "trash", isDestructive = true) { isConfirmingDelete = true }
                IosMenu(open, { open = false }, actions)
            }
        },
    ) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = Spacing.medium, bottom = Spacing.large)) {
            if (template.instructions.isNotEmpty()) {
                SectionTitle(L10n.Templates.instructions)
                Text(template.instructions, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.padding(horizontal = Spacing.medium, vertical = Spacing.small))
                Spacer(Modifier.height(Spacing.medium))
            }
            SectionTitle(L10n.Templates.sections)
            template.sections.forEachIndexed { index, section ->
                Row(Modifier.fillMaxWidth().heightIn(min = TapTarget).padding(horizontal = Spacing.medium), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.medium)) {
                    SfIcon(if (section.kind == SectionKind.TASKS) "checklist" else "list.bullet", tint = Ds.action.value)
                    Text(L10n.Summary.sectionTitle(section.title), style = DsType.rowTitle, color = Ds.primaryText.value)
                }
                if (index < template.sections.lastIndex) RowDivider(Modifier.padding(start = 56.dp, end = Spacing.medium))
            }
            if (transcribed.isNotEmpty()) {
                Spacer(Modifier.height(Spacing.medium))
                SectionTitle(L10n.Templates.tryOn)
                for (recording in transcribed.take(5)) {
                    TextAction(recording.title, Modifier.padding(horizontal = Spacing.medium)) {
                        scope.launch {
                            if (center.summarize(recording.id, template, null) == TranscribeOutcome.NEEDS_MODEL) router.push(AppRoute.ModelSettings) else router.push(AppRoute.Recording(recording.id))
                        }
                    }
                }
            }
        }
    }
    editing?.let { draft -> TemplateEditor(draft, onSave = { scope.launch { center.save(it) } }) { editing = null } }
    if (isConfirmingDelete) {
        IosAlert(
            L10n.Templates.delete, null,
            listOf(AlertButton(L10n.Common.cancel, AlertButton.Role.CANCEL), AlertButton(L10n.Library.delete, AlertButton.Role.DESTRUCTIVE) { scope.launch { center.delete(template); router.pop() } }),
            onDismiss = { isConfirmingDelete = false },
        )
    }
}

@Composable
fun TemplateEditor(initial: SummaryTemplate, onSave: (SummaryTemplate) -> Unit, onDismiss: () -> Unit) {
    var template by remember { mutableStateOf(initial) }
    // A section's identity must not come from its text, or the field loses the keyboard on every letter.
    val rows = remember { mutableStateListOf<Pair<Long, TemplateSection>>().apply { addAll(initial.sections.mapIndexed { index, section -> index.toLong() to section }) } }
    var next by remember { mutableStateOf(initial.sections.size.toLong()) }
    val draft = template.copy(sections = rows.map { it.second })
    var categoryOpen by remember { mutableStateOf(false) }
    IosSheet(onDismiss) {
        SheetBar(
            L10n.Templates.new,
            leading = { TextAction(L10n.Common.cancel, color = Ds.primaryText.value, onClick = onDismiss) },
            trailing = { TextAction(L10n.Common.save, Modifier.testTag("template.save"), enabled = TemplateCodec.isValid(draft), style = DsType.heading) { onSave(draft); onDismiss() } },
        )
        SheetBody(Modifier.padding(top = Spacing.medium)) {
            FormSection {
                FormTextField(template.name, { template = template.copy(name = it) }, L10n.Templates.name, Modifier.testTag("template.name"))
                FormRow(divider = false, onClick = { categoryOpen = true }) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(L10n.Templates.categoryLabel, style = DsType.rowTitle, color = Ds.primaryText.value, modifier = Modifier.weight(1f))
                        Box {
                            Text(template.category.title, style = DsType.rowTitle, color = Ds.secondaryText.value)
                            IosMenu(categoryOpen, { categoryOpen = false }, TemplateCategory.entries.map { category -> MenuAction(category.title, isChecked = category == template.category) { template = template.copy(category = category) } })
                        }
                    }
                }
            }
            FormSection(L10n.Templates.instructions) {
                FormTextField(template.instructions, { template = template.copy(instructions = it) }, L10n.Templates.instructionsHint, Modifier.heightIn(min = 90.dp), divider = false, singleLine = false)
            }
            FormSection(L10n.Templates.sections, footer = if (!TemplateCodec.isValid(draft)) L10n.Templates.saveHint else null) {
                rows.forEachIndexed { index, (key, section) ->
                    androidx.compose.runtime.key(key) {
                        SwipeRow(trailing = listOf(SwipeAction(L10n.Library.delete, "trash", Ds.record.value) { rows.removeAt(index) })) {
                            Column(Modifier.background(Ds.surface.value)) {
                                FormTextField(section.title, { rows[index] = key to section.copy(title = it) }, L10n.Templates.sectionTitle, Modifier.testTag("template.section"), divider = false)
                                Box(Modifier.padding(horizontal = Spacing.medium, vertical = Spacing.small)) {
                                    SegmentedControl(listOf(L10n.Templates.kindBullets, L10n.Templates.kindTasks), section.kind.ordinal, { rows[index] = key to section.copy(kind = SectionKind.entries[it]) })
                                }
                                RowDivider(Modifier.padding(start = Spacing.medium + 4.dp))
                            }
                        }
                    }
                }
                FormButton(L10n.Templates.addSection, symbol = "plus", enabled = rows.size < TemplateCodec.Limits.SECTIONS, divider = false) {
                    rows.add(next to TemplateSection(""))
                    next++
                }
            }
        }
    }
}

/** Describe it in plain words, and get a template to edit. */
@Composable
private fun TemplateDraftSheet(center: SummaryCenter, onDraft: (SummaryTemplate) -> Unit, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var description by remember { mutableStateOf("") }
    var isWorking by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    IosSheet(onDismiss) {
        SheetBar(
            L10n.Templates.createWithAI,
            leading = { TextAction(L10n.Common.cancel, color = Ds.primaryText.value, onClick = onDismiss) },
            trailing = {
                TextAction(L10n.Templates.aiGenerate, Modifier.testTag("template.ai.generate"), enabled = !isWorking && description.isNotBlank(), style = DsType.heading) {
                    isWorking = true
                    failure = null
                    scope.launch {
                        try {
                            if (!center.hasLanguageModel()) {
                                failure = L10n.Templates.needsModel
                                return@launch
                            }
                            val template = center.draftTemplate(description)
                            onDismiss()
                            onDraft(template)
                        } catch (_: Exception) {
                            failure = L10n.Templates.aiFailed
                        } finally {
                            isWorking = false
                        }
                    }
                }
            },
        )
        SheetBody(Modifier.padding(top = Spacing.medium)) {
            FormSection(L10n.Templates.aiPrompt) {
                FormTextField(description, { description = it }, L10n.Templates.aiHint, Modifier.heightIn(min = 120.dp).testTag("template.ai.description"), divider = false, singleLine = false)
            }
            if (isWorking) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { ProgressRing(null) }
            failure?.let { Text(it, style = DsType.rowTitle, color = Ds.record.value, modifier = Modifier.padding(horizontal = Spacing.large)) }
        }
    }
}

// MARK: - Connectors

/** What can be connected, by category. It reads the registry and knows no connector by name. */
@Composable
private fun ConnectorsTab(registry: ConnectorRegistry, settings: (String) -> ConnectorSettings?) {
    var selected by remember { mutableStateOf<ConnectorManifest?>(null) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = com.meetlaud.app.shell.contentPadding(top = Spacing.small)) {
        for (category in registry.categories) {
            item("header.$category") { SectionTitle(L10n.Connectors.productivity) }
            items(registry.manifests(category), key = { it.id }) { connector ->
                PlainButton({ selected = connector }, Modifier.fillMaxWidth().padding(horizontal = Spacing.medium, vertical = 11.dp).testTag("connector.${connector.id}")) {
                    ConnectorIconView(connector.icon)
                    Spacer(Modifier.width(Spacing.compact))
                    RowLabel(connector.name, L10n.Connectors.localWiFi, Modifier.weight(1f))
                    val linked = registry.connector(connector.id)?.linkedSince != null
                    if (connector.availability == ConnectorManifest.Availability.COMING_SOON || linked) {
                        Text(if (connector.availability == ConnectorManifest.Availability.COMING_SOON) L10n.Common.comingSoon else L10n.Connectors.connected, style = DsType.badge, color = Ds.secondaryText.value)
                        Spacer(Modifier.width(Spacing.small))
                    }
                    SfIcon("chevron.right", tint = Ds.secondaryText.value, size = DsType.note.fontSize)
                }
                RowDivider(Modifier.padding(horizontal = Spacing.medium))
            }
        }
        item("note") { Text(L10n.Connectors.note, style = DsType.note, color = Ds.secondaryText.value, modifier = Modifier.padding(Spacing.medium)) }
    }
    selected?.let { manifest -> ConnectorSheet(manifest, registry, settings(manifest.id)) { selected = null } }
}

@Composable
private fun ConnectorIconView(icon: ConnectorIcon, size: androidx.compose.ui.unit.Dp = 28.dp) {
    when (icon) {
        is ConnectorIcon.Symbol -> SfIcon(icon.name, size, tint = Ds.secondaryText.value)
        is ConnectorIcon.Image -> {
            val bitmap = remember(icon.file) { android.graphics.BitmapFactory.decodeFile(icon.file.path) }
            if (bitmap != null) androidx.compose.foundation.Image(bitmap.asImageBitmap(), null, Modifier.size(size))
        }
    }
}

private val ConnectorContent.title: String
    get() = when (this) {
        ConnectorContent.AUDIO -> L10n.Connectors.contentAudio
        ConnectorContent.TRANSCRIPT -> L10n.Connectors.contentTranscript
        ConnectorContent.PHOTOS -> L10n.Connectors.contentPhotos
        ConnectorContent.NOTES -> L10n.Connectors.contentNotes
    }

private val ConnectorContent.symbol: String
    get() = when (this) {
        ConnectorContent.AUDIO -> "waveform"
        ConnectorContent.TRANSCRIPT -> "text.alignleft"
        ConnectorContent.PHOTOS -> "photo"
        ConnectorContent.NOTES -> "square.and.pencil"
    }

/** What the other app is, what it would receive, and the way to start. */
@Composable
private fun ConnectorSheet(manifest: ConnectorManifest, registry: ConnectorRegistry, settings: ConnectorSettings?, onDismiss: () -> Unit) {
    var isOpen by remember { mutableStateOf(false) }
    val isConnected = registry.connector(manifest.id)?.linkedSince != null
    IosSheet(onDismiss, large = false) {
        SheetBody(Modifier.padding(Spacing.large).testTag("screen.connector")) {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.medium)) {
                ConnectorIconView(manifest.icon, 56.dp)
                SheetHeader(manifest.name, L10n.Common.close, onDismiss)
                Text(manifest.summary, style = DsType.rowTitle, color = Ds.primaryText.value)
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.small)) {
                    Text(L10n.Connectors.shares, style = DsType.heading, color = Ds.primaryText.value, modifier = Modifier.semantics { heading() })
                    for (content in ConnectorContent.entries.filter { it in manifest.accepts }) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
                            SfIcon(content.symbol, tint = Ds.secondaryText.value, size = DsType.meta.fontSize)
                            Text(content.title, style = DsType.meta, color = Ds.secondaryText.value)
                        }
                    }
                }
                Text(L10n.Connectors.localWiFi, style = DsType.note, color = Ds.secondaryText.value)
                val title = when {
                    manifest.availability != ConnectorManifest.Availability.AVAILABLE -> L10n.Common.comingSoon
                    isConnected -> L10n.Connectors.manage
                    else -> L10n.Connectors.connect
                }
                PrimaryAction(title, Modifier.fillMaxWidth().testTag("connector.connect"), enabled = manifest.availability == ConnectorManifest.Availability.AVAILABLE && settings != null) { isOpen = true }
            }
        }
    }
    if (isOpen && settings != null) {
        IosSheet({ isOpen = false }) {
            SheetBar(manifest.name, leading = { TextAction(L10n.Common.done, color = Ds.primaryText.value) { isOpen = false } })
            settings.Content { isOpen = false }
        }
    }
}
