package com.meetlaud.app.feature.shared

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.localization.builtInName
import com.meetlaud.app.localization.builtInSummary
import com.meetlaud.domain.BuiltInSkills
import com.meetlaud.domain.Preferences
import com.meetlaud.domain.Skill
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/** The person's own skills, on this device only, as SkillLibrary.swift. Tools edits them and Ask uses them. */
class SkillLibrary(private val defaults: Preferences) {
    private val json = Json { ignoreUnknownKeys = true }
    private val serializer = ListSerializer(Skill.serializer())

    var mine by mutableStateOf(defaults.string(KEY)?.let { runCatching { json.decodeFromString(serializer, it) }.getOrNull() } ?: emptyList())
        private set

    companion object {
        private const val KEY = "tools.skills"
    }

    val all: List<Skill> get() = mine + BuiltInSkills.all

    fun skill(id: String): Skill? = all.firstOrNull { it.id == id }

    fun save(skill: Skill) {
        if (!skill.isValid || skill.isBuiltIn) return
        val index = mine.indexOfFirst { it.id == skill.id }
        mine = if (index >= 0) mine.toMutableList().also { it[index] = skill } else listOf(skill) + mine
        persist()
    }

    fun delete(skill: Skill) {
        mine = mine.filter { it.id != skill.id }
        persist()
    }

    private fun persist() = defaults.setString(KEY, json.encodeToString(serializer, mine))
}

val Skill.displayName: String get() = if (isBuiltIn) L10n.Skills.builtInName(name) else name

val Skill.displaySummary: String get() = if (isBuiltIn) L10n.Skills.builtInSummary(summary) else summary
