package com.meetlaud.domain

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.util.UUID

/**
 * A prompt recipe: instructions that shape how the chat answers. Skills change the form of an answer and never its
 * sources, so the rule that every statement comes from a transcript still holds.
 */
@Serializable
data class Skill(
    val id: String = UUID.randomUUID().uuidString,
    val name: String,
    val summary: String,
    val instructions: String,
    val isBuiltIn: Boolean = false,
) {
    companion object {
        const val INSTRUCTIONS_LIMIT = 1500
    }

    val isValid: Boolean get() = name.trimmedWhitespace().isNotEmpty() && instructions.trimmedWhitespace().isNotEmpty()
}

/** The skills that come with the app. Names and summaries are identifiers: the interface translates them. */
object BuiltInSkills {
    val all = listOf(
        Skill("builtin.followup", "followup", "followup", "Write a short follow-up email: a thank you, the decisions, and who does what next.", true),
        Skill("builtin.brief", "brief", "brief", "Answer as a brief for an executive: three lines at most, the outcome first.", true),
        Skill("builtin.objections", "objections", "objections", "List the objections and concerns people raised, and how each one was answered.", true),
    )
}

/**
 * A skill as a file. Files come from other people, so nothing in them is trusted: a file can never replace a skill or
 * pass for a built-in one.
 */
object SkillCodec {
    @Serializable
    private data class FileFormat(val instructions: String, val name: String, val summary: String? = null)

    class InvalidSkill : Exception("invalid")

    private val reader = Json { ignoreUnknownKeys = true }
    private val writer = Json { prettyPrint = true }

    fun decode(data: ByteArray): Skill {
        val file = runCatching { reader.decodeFromString(FileFormat.serializer(), data.decodeToString()) }.getOrElse { throw InvalidSkill() }
        if (file.name.codePointCount(0, file.name.length) > 80 || file.instructions.codePointCount(0, file.instructions.length) > Skill.INSTRUCTIONS_LIMIT) throw InvalidSkill()
        val skill = Skill(name = file.name, summary = file.summary ?: "", instructions = file.instructions)
        if (!skill.isValid) throw InvalidSkill()
        return skill
    }

    /** Keys sorted, as the iOS app writes them, so a file reads the same from either app. */
    fun encode(skill: Skill): ByteArray =
        writer.encodeToString(FileFormat.serializer(), FileFormat(skill.instructions, skill.name, skill.summary)).encodeToByteArray()
}

/** Whether meeting titles can appear in system search. Off until the person turns it on. */
object SpotlightPreferences {
    const val KEY = "privacy.spotlight"
}

/** The system's search index, on this device. Only titles and dates go in. */
interface SystemSearchIndex {
    suspend fun index(recordings: List<Recording>)
    suspend fun removeAll()
}
