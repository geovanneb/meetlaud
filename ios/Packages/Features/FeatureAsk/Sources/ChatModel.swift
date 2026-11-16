import Domain
import Foundation
import Observation

@MainActor
@Observable
final class ChatModel {
    enum Status: Equatable {
        case idle, waiting, searching, writing
    }

    private(set) var conversation: Conversation
    private(set) var messages: [ChatMessage] = []
    private(set) var status = Status.idle
    /// The answer as it arrives.
    private(set) var partial = ""
    private(set) var hasLanguageModel = true
    /// Shapes every answer in this chat. It is not stored: a skill belongs to the moment it was chosen.
    var skill: Skill?

    @ObservationIgnored private let coordinator: AskCoordinator
    @ObservationIgnored private let store: any ConversationStore
    @ObservationIgnored private let manager: ModelManager
    @ObservationIgnored private let onChange: @MainActor () async -> Void
    @ObservationIgnored private let startingMeeting: RecordingID?

    init(
        conversation: Conversation,
        coordinator: AskCoordinator,
        store: any ConversationStore,
        manager: ModelManager,
        onChange: @escaping @MainActor () async -> Void,
    ) {
        self.conversation = conversation
        startingMeeting = conversation.scope.recordingID
        self.coordinator = coordinator
        self.store = store
        self.manager = manager
        self.onChange = onChange
    }

    var isBusy: Bool {
        status != .idle
    }

    func load() async {
        messages = await (try? store.messages(in: conversation.id)) ?? []
        hasLanguageModel = await manager.model(for: .chat, language: nil) != nil
    }

    /// The meeting this chat was opened from, so that the menu can always go back to it.
    var meeting: RecordingID? {
        startingMeeting ?? conversation.scope.recordingID
    }

    /// The earlier answers came from the old scope, and the model would read them as part of the new one. So once
    /// a chat has messages, a new scope starts a new chat, and the old one stays in the list.
    func setScope(_ scope: AskScope) async {
        guard scope != conversation.scope, !isBusy else { return }
        if messages.isEmpty {
            conversation.scope = scope
        } else {
            conversation = Conversation(scope: scope, createdAt: Date())
            messages = []
            partial = ""
        }
    }

    func send(_ question: String) async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        status = .searching
        partial = ""
        messages.append(ChatMessage(conversationID: conversation.id, role: .user, body: text, createdAt: Date()))
        let model = await manager.model(for: .chat, language: nil)
        for await update in await coordinator.ask(
            text,
            in: conversation,
            modelID: model?.id,
            skill: skill?.instructions,
        ) {
            switch update {
            case .waiting: status = .waiting
            case .searching: status = .searching
            case let .writing(text):
                status = .writing
                partial = text
            case let .finished(message):
                messages.append(message)
                partial = ""
            }
        }
        status = .idle
        // The title comes from the first question, and it is written on the way through the coordinator.
        await onChange()
        if let saved = await (try? store.conversations())?.first(where: { $0.id == conversation.id }) {
            conversation = saved
        }
    }

    func stop() {
        Task { await coordinator.stop() }
    }
}
