package com.meetlaud.app.feature.ask

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.meetlaud.domain.AskCoordinator
import com.meetlaud.domain.AskScope
import com.meetlaud.domain.AskUpdate
import com.meetlaud.domain.ChatMessage
import com.meetlaud.domain.ChatRole
import com.meetlaud.domain.Conversation
import com.meetlaud.domain.ConversationStore
import com.meetlaud.domain.Folder
import com.meetlaud.domain.IndexProgress
import com.meetlaud.domain.KnowledgeIndexer
import com.meetlaud.domain.MemoryItem
import com.meetlaud.domain.ModelManager
import com.meetlaud.domain.ModelRole
import com.meetlaud.domain.RecordingID
import com.meetlaud.domain.RecordingStore
import com.meetlaud.domain.Skill
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.time.Instant

/** Chat history, memory, and the search index, for the life of the app, as AskController.swift. */
class AskController(
    private val coordinator: AskCoordinator,
    private val indexer: KnowledgeIndexer,
    private val store: ConversationStore,
    private val recordings: RecordingStore,
    private val manager: ModelManager,
    private val scope: CoroutineScope,
) {
    var conversations by mutableStateOf<List<Conversation>>(emptyList())
        private set
    var memories by mutableStateOf<List<MemoryItem>>(emptyList())
        private set
    var folders by mutableStateOf<List<Folder>>(emptyList())
        private set
    var indexing by mutableStateOf<IndexProgress?>(null)
        private set

    init {
        scope.launch { indexer.updates.collect { indexing = it } }
        scope.launch { recordings.observeFolders().collect { folders = it } }
    }

    suspend fun reload() {
        conversations = runCatching { store.conversations() }.getOrDefault(emptyList())
        memories = runCatching { store.memories() }.getOrDefault(emptyList())
    }

    /** Asks for the search models the first time someone comes here, then indexes with them. */
    suspend fun prepareSearch() {
        manager.installSearchModelIfNeeded()
        indexer.run()
    }

    fun chat(conversation: Conversation): ChatModel = ChatModel(conversation, coordinator, store, manager, scope) { reload() }

    fun newChat(scope: AskScope): ChatModel = chat(Conversation(scope = scope, createdAt = Instant.now()))

    /** Picks up the last chat about this meeting or folder, so that coming back continues the same thread. */
    suspend fun chat(about: AskScope): ChatModel {
        reload()
        return conversations.firstOrNull { it.scope == about }?.let(::chat) ?: newChat(about)
    }

    suspend fun title(id: RecordingID): String? = runCatching { recordings.recording(id)?.title }.getOrNull()

    suspend fun rename(conversation: Conversation, title: String) {
        val trimmed = title.trim()
        if (trimmed.isEmpty()) return
        runCatching { store.save(conversation.copy(title = trimmed)) }
        reload()
    }

    suspend fun delete(conversation: Conversation) {
        runCatching { store.deleteConversation(conversation.id) }
        reload()
    }

    suspend fun addMemory(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        runCatching { store.save(MemoryItem(text = trimmed, createdAt = Instant.now())) }
        reload()
    }

    suspend fun update(memory: MemoryItem, text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        runCatching { store.save(memory.copy(text = trimmed)) }
        reload()
    }

    suspend fun delete(memory: MemoryItem) {
        runCatching { store.deleteMemory(memory.id) }
        reload()
    }
}

/** One chat, as ChatModel.swift. */
class ChatModel(
    conversation: Conversation,
    private val coordinator: AskCoordinator,
    private val store: ConversationStore,
    private val manager: ModelManager,
    private val scope: CoroutineScope,
    private val onChange: suspend () -> Unit,
) {
    enum class Status { IDLE, WAITING, SEARCHING, WRITING }

    var conversation by mutableStateOf(conversation)
        private set
    var messages by mutableStateOf<List<ChatMessage>>(emptyList())
        private set
    var status by mutableStateOf(Status.IDLE)
        private set
    /** The answer as it arrives. */
    var partial by mutableStateOf("")
        private set
    var hasLanguageModel by mutableStateOf(true)
        private set
    /** Shapes every answer in this chat. It is not stored: a skill belongs to the moment it was chosen. */
    var skill by mutableStateOf<Skill?>(null)
    private val startingMeeting = conversation.scope.recordingID

    val isBusy: Boolean get() = status != Status.IDLE

    suspend fun load() {
        messages = runCatching { store.messages(conversation.id) }.getOrDefault(emptyList())
        hasLanguageModel = manager.model(ModelRole.CHAT, null) != null
    }

    /** The meeting this chat was opened from, so that the menu can always go back to it. */
    val meeting: RecordingID? get() = startingMeeting ?: conversation.scope.recordingID

    /** Once a chat has messages, a new scope starts a new chat, and the old one stays in the list. */
    fun setScope(next: AskScope) {
        if (next == conversation.scope || isBusy) return
        if (messages.isEmpty()) {
            conversation = conversation.copy(scope = next)
        } else {
            conversation = Conversation(scope = next, createdAt = Instant.now())
            messages = emptyList()
            partial = ""
        }
    }

    fun send(question: String) {
        val text = question.trim()
        if (text.isEmpty() || isBusy) return
        status = Status.SEARCHING
        partial = ""
        messages = messages + ChatMessage(conversationID = conversation.id, role = ChatRole.USER, body = text, createdAt = Instant.now())
        scope.launch {
            val model = manager.model(ModelRole.CHAT, null)
            coordinator.ask(text, conversation, model?.id, skill?.instructions).collect { update ->
                when (update) {
                    AskUpdate.Waiting -> status = Status.WAITING
                    AskUpdate.Searching -> status = Status.SEARCHING
                    is AskUpdate.Writing -> {
                        status = Status.WRITING
                        partial = update.text
                    }
                    is AskUpdate.Finished -> {
                        messages = messages + update.message
                        partial = ""
                    }
                }
            }
            status = Status.IDLE
            // The title comes from the first question, and it is written on the way through the coordinator.
            onChange()
            runCatching { store.conversations() }.getOrNull()?.firstOrNull { it.id == conversation.id }?.let { conversation = it }
        }
    }

    fun stop() {
        scope.launch { coordinator.stop() }
    }
}
