import Domain
import Foundation
import Observation

/// Chat history, memory, and the search index, for the life of the app.
@MainActor
@Observable
public final class AskController {
    public private(set) var conversations: [Conversation] = []
    public private(set) var memories: [MemoryItem] = []
    public private(set) var folders: [Folder] = []
    public private(set) var indexing: IndexProgress?

    @ObservationIgnored private let coordinator: AskCoordinator
    @ObservationIgnored private let store: any ConversationStore
    @ObservationIgnored private let recordings: any RecordingStore
    @ObservationIgnored private let manager: ModelManager
    @ObservationIgnored private let indexer: KnowledgeIndexer
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    public init(
        coordinator: AskCoordinator,
        indexer: KnowledgeIndexer,
        store: any ConversationStore,
        recordings: any RecordingStore,
        manager: ModelManager,
    ) {
        self.coordinator = coordinator
        self.store = store
        self.recordings = recordings
        self.manager = manager
        self.indexer = indexer
        tasks.append(Task { [weak self] in
            for await progress in indexer.updates {
                self?.indexing = progress
            }
        })
        tasks.append(Task { [weak self] in
            for await folders in recordings.observeFolders() {
                self?.folders = folders
            }
        })
    }

    deinit {
        tasks.forEach { $0.cancel() }
    }

    public func reload() async {
        conversations = await (try? store.conversations()) ?? []
        memories = await (try? store.memories()) ?? []
    }

    /// Asks iOS for the search models the first time someone comes here, then indexes with them.
    func prepareSearch() async {
        await manager.installSearchModelIfNeeded()
        await indexer.run()
    }

    func chat(_ conversation: Conversation) -> ChatModel {
        ChatModel(conversation: conversation, coordinator: coordinator, store: store, manager: manager) { [weak self] in
            await self?.reload()
        }
    }

    func newChat(scope: AskScope) -> ChatModel {
        chat(Conversation(scope: scope, createdAt: Date()))
    }

    /// Picks up the last chat about this meeting or folder, so that coming back continues the same thread.
    func chat(about scope: AskScope) async -> ChatModel {
        await reload()
        return conversations.first { $0.scope == scope }.map(chat) ?? newChat(scope: scope)
    }

    func title(of id: RecordingID) async -> String? {
        await (try? recordings.recording(id))?.title
    }

    func rename(_ conversation: Conversation, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var conversation = conversation
        conversation.title = trimmed
        try? await store.save(conversation)
        await reload()
    }

    func delete(_ conversation: Conversation) async {
        try? await store.deleteConversation(conversation.id)
        await reload()
    }

    func addMemory(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await store.save(MemoryItem(text: trimmed, createdAt: Date()))
        await reload()
    }

    func update(_ memory: MemoryItem, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var memory = memory
        memory.text = trimmed
        try? await store.save(memory)
        await reload()
    }

    func delete(_ memory: MemoryItem) async {
        try? await store.deleteMemory(memory.id)
        await reload()
    }
}
