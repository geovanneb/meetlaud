package com.meetlaud.domain

import kotlinx.coroutines.flow.Flow
import java.time.Instant
import java.util.UUID

/** How much of the library a chat can read. */
sealed interface AskScope {
    data object Library : AskScope
    data class Folder(val id: FolderID) : AskScope
    data class Recording(val id: RecordingID) : AskScope

    val recordingID: RecordingID? get() = (this as? Recording)?.id
    val folderID: FolderID? get() = (this as? Folder)?.id
}

data class Conversation(
    val id: UUID = UUID.randomUUID(),
    val title: String = "",
    val scope: AskScope,
    val createdAt: Instant,
    val updatedAt: Instant = createdAt,
)

enum class ChatRole(val raw: String) {
    USER("user"), ASSISTANT("assistant");

    companion object {
        fun from(raw: String): ChatRole? = entries.firstOrNull { it.raw == raw }
    }
}

enum class AnswerState(val raw: String) {
    /** Every answer of this kind has at least one citation that points at real text. */
    COMPLETE("complete"),
    /** The person stopped it, or the app had to. Whatever was written stays. */
    STOPPED("stopped"),
    /** Nothing in scope answers this. `body` is empty, and the screen says so in the reader's language. */
    NO_BASIS("noBasis"),
    /** `body` holds what was saved to memory. */
    REMEMBERED("remembered"),
    FAILED("failed");

    companion object {
        fun from(raw: String): AnswerState? = entries.firstOrNull { it.raw == raw }
    }
}

/** Where an answer's statement came from. `number` is the `[1]` shown in the text. */
data class Citation(
    val number: Int,
    val recordingID: RecordingID,
    val recordingTitle: String,
    val time: TimeInterval,
    val excerpt: String,
)

data class ChatMessage(
    val id: UUID = UUID.randomUUID(),
    val conversationID: UUID,
    val role: ChatRole,
    val body: String,
    val citations: List<Citation> = emptyList(),
    val state: AnswerState = AnswerState.COMPLETE,
    val createdAt: Instant,
)

/** Something the person asked the app to keep in mind, for every chat. */
data class MemoryItem(val id: UUID = UUID.randomUUID(), val text: String, val createdAt: Instant)

/** A stretch of a transcript, small enough to search and to quote. */
data class KnowledgeChunk(
    val id: UUID = UUID.randomUUID(),
    val recordingID: RecordingID,
    val start: TimeInterval,
    val end: TimeInterval,
    val text: String,
    val language: String? = null,
    /** Vectors from different models mean nothing to each other. Null when no model covers this text. */
    val modelID: String? = null,
    val vector: List<Float>? = null,
)

/** What the index was built from. Any difference means the chunks are stale. */
data class KnowledgeIndexState(val sourceHash: String, val modelID: String?)

data class IndexProgress(val done: Int, val total: Int) {
    val fraction: Double get() = if (total == 0) 1.0 else done.toDouble() / total
}

/** What a search model's speed test measured. */
data class SearchSpeed(val modelID: String, val passagesPerSecond: Double) {
    companion object {
        /** About what a minute of a meeting turns into. */
        const val SAMPLE = "We agreed to move the launch to the second week of March, because the payment provider is not ready yet, and " +
            "Maria will send the updated budget to finance by Friday so that the team can plan the next quarter."
        /** An hour of speech is about 9,000 words, which makes this many passages. */
        private const val PASSAGES_PER_HOUR = 115.0
    }

    val secondsPerHourOfAudio: Int get() = maxOf(1, Math.round(PASSAGES_PER_HOUR / maxOf(passagesPerSecond, 0.001)).toInt())
}

sealed interface AskUpdate {
    /** Another model is working, and this question is next. */
    data object Waiting : AskUpdate
    data object Searching : AskUpdate
    /** The answer so far, without the parts that are not for reading. */
    data class Writing(val text: String) : AskUpdate
    data class Finished(val message: ChatMessage) : AskUpdate
}

object AskPreferences {
    const val PROMPT_BAR_KEY = "ask.promptBar"

    /** What the prompt bar on a meeting does. */
    enum class PromptBar(val raw: String) {
        FOCUS("focus"), NEW_CHAT("newChat");

        companion object {
            fun from(raw: String?): PromptBar = entries.firstOrNull { it.raw == raw } ?: FOCUS
        }
    }
}

/** Turns text into vectors that sit close together when the meaning is close. */
interface TextEmbeddingEngine : ModelRunner {
    /** Null when nothing on the device covers this language right now. */
    suspend fun modelID(language: String?): String?
    suspend fun detectLanguage(text: String): String?
    /** Returns one unit-length vector per text, all from `modelID(language)`. */
    suspend fun embed(texts: List<String>, language: String?): List<List<Float>>
}

interface ConversationStore {
    /** Most recently used first. */
    suspend fun conversations(): List<Conversation>
    suspend fun save(conversation: Conversation)
    suspend fun deleteConversation(id: UUID)
    suspend fun messages(conversation: UUID): List<ChatMessage>
    suspend fun save(message: ChatMessage)

    suspend fun memories(): List<MemoryItem>
    suspend fun save(memory: MemoryItem)
    suspend fun deleteMemory(id: UUID)
}

interface KnowledgeStore {
    suspend fun indexStates(): Map<RecordingID, KnowledgeIndexState>
    /** One transaction, so that a recording is never left half indexed. */
    suspend fun replaceChunks(chunks: List<KnowledgeChunk>, id: RecordingID, state: KnowledgeIndexState)
    suspend fun removeChunks(id: RecordingID)
    /** Best first. Recordings in the trash never match. */
    suspend fun lexicalMatches(terms: List<String>, scope: AskScope, limit: Int): List<UUID>
    /** Best first, among chunks from the same model. Recordings in the trash never match. */
    suspend fun nearest(vector: List<Float>, modelID: String, scope: AskScope, limit: Int): List<UUID>
    suspend fun chunks(ids: List<UUID>): List<KnowledgeChunk>
}
