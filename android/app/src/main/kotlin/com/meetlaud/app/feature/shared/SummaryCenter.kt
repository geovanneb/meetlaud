package com.meetlaud.app.feature.shared

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.meetlaud.app.localization.Strings
import com.meetlaud.domain.BuiltInTemplates
import com.meetlaud.domain.ModelManager
import com.meetlaud.domain.ModelRole
import com.meetlaud.domain.Preferences
import com.meetlaud.domain.RecordingID
import com.meetlaud.domain.Summary
import com.meetlaud.domain.SummaryCoordinator
import com.meetlaud.domain.SummaryPreferences
import com.meetlaud.domain.SummaryProgress
import com.meetlaud.domain.SummaryStore
import com.meetlaud.domain.SummaryTemplate
import com.meetlaud.domain.TemplateCodec
import com.meetlaud.domain.TemplateException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.util.UUID

/** Starts summaries and holds templates, from any screen, as SummaryCenter.swift. There is one for the life of the app. */
class SummaryCenter(
    private val coordinator: SummaryCoordinator,
    private val manager: ModelManager,
    private val store: SummaryStore,
    private val defaults: Preferences,
    scope: CoroutineScope,
) {
    var progress by mutableStateOf<Map<UUID, SummaryProgress>>(emptyMap())
        private set
    var userTemplates by mutableStateOf<List<SummaryTemplate>>(emptyList())
        private set
    var defaultTemplateID by mutableStateOf(defaults.string(SummaryPreferences.DEFAULT_TEMPLATE_KEY) ?: BuiltInTemplates.DEFAULT_ID)
        private set

    init {
        scope.launch { coordinator.updates.collect { progress = it } }
    }

    val templates: List<SummaryTemplate> get() = BuiltInTemplates.all + userTemplates

    val defaultTemplate: SummaryTemplate get() = templates.firstOrNull { it.id == defaultTemplateID } ?: BuiltInTemplates.all[0]

    fun setDefault(template: SummaryTemplate) {
        defaultTemplateID = template.id
        defaults.setString(SummaryPreferences.DEFAULT_TEMPLATE_KEY, template.id)
    }

    suspend fun reloadTemplates() {
        userTemplates = runCatching { store.userTemplates() }.getOrDefault(emptyList())
    }

    suspend fun save(template: SummaryTemplate) {
        runCatching { store.save(template) }
        reloadTemplates()
    }

    suspend fun delete(template: SummaryTemplate) {
        runCatching { store.deleteTemplate(template.id) }
        reloadTemplates()
    }

    suspend fun importTemplate(data: ByteArray): SummaryTemplate {
        val template = TemplateCodec.decode(data)
        save(template)
        return template
    }

    suspend fun hasLanguageModel(): Boolean = manager.model(ModelRole.CHAT, null) != null

    suspend fun draftTemplate(description: String): SummaryTemplate {
        val model = manager.model(ModelRole.CHAT, null) ?: throw TemplateException()
        return coordinator.draftTemplate(description, model.id, Strings.locale().language)
    }

    suspend fun summarize(id: RecordingID, template: SummaryTemplate, language: String?): TranscribeOutcome {
        val model = manager.model(ModelRole.CHAT, language) ?: return TranscribeOutcome.NEEDS_MODEL
        runCatching { coordinator.enqueue(id, template, model.id, language) }
        return TranscribeOutcome.STARTED
    }

    suspend fun cancel(id: UUID) {
        runCatching { coordinator.cancel(id) }
    }

    suspend fun summaries(id: RecordingID): List<Summary> = runCatching { store.summaries(id) }.getOrDefault(emptyList())

    suspend fun save(summary: Summary) {
        runCatching { store.save(summary) }
    }

    suspend fun delete(summary: Summary) {
        runCatching { store.deleteSummary(summary.id) }
    }
}
