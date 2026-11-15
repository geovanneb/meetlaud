import Foundation

/// How much of the library a chat can read.
public enum AskScope: Hashable, Codable, Sendable {
    case library
    case folder(FolderID)
    case recording(RecordingID)

    public var recordingID: RecordingID? {
        if case let .recording(id) = self {
            id
        } else {
            nil
        }
    }

    public var folderID: FolderID? {
        if case let .folder(id) = self {
            id
        } else {
            nil
        }
    }
}

public struct Conversation: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var scope: AskScope
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String = "", scope: AskScope, createdAt: Date, updatedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.scope = scope
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

public enum ChatRole: String, Codable, Sendable {
    case user, assistant
}

public enum AnswerState: String, Codable, Sendable {
    /// Every answer of this kind has at least one citation that points at real text.
    case complete
    /// The person stopped it, or the app had to. Whatever was written stays.
    case stopped
    /// Nothing in scope answers this. `body` is empty, and the screen says so in the reader's language.
    case noBasis
    /// `body` holds what was saved to memory.
    case remembered
    case failed
}

/// Where an answer's statement came from. `number` is the `[1]` shown in the text.
public struct Citation: Hashable, Codable, Sendable {
    public let number: Int
    public let recordingID: RecordingID
    public let recordingTitle: String
    public let time: TimeInterval
    public let excerpt: String

    public init(number: Int, recordingID: RecordingID, recordingTitle: String, time: TimeInterval, excerpt: String) {
        self.number = number
        self.recordingID = recordingID
        self.recordingTitle = recordingTitle
        self.time = time
        self.excerpt = excerpt
    }
}

public struct ChatMessage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let conversationID: UUID
    public let role: ChatRole
    public var body: String
    public var citations: [Citation]
    public var state: AnswerState
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        conversationID: UUID,
        role: ChatRole,
        body: String,
        citations: [Citation] = [],
        state: AnswerState = .complete,
        createdAt: Date,
    ) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.body = body
        self.citations = citations
        self.state = state
        self.createdAt = createdAt
    }
}

/// Something the person asked the app to keep in mind, for every chat.
public struct MemoryItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var text: String
    public let createdAt: Date

    public init(id: UUID = UUID(), text: String, createdAt: Date) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// A stretch of a transcript, small enough to search and to quote.
public struct KnowledgeChunk: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let recordingID: RecordingID
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String
    public let language: String?
    /// Vectors from different models mean nothing to each other. Nil when no model covers this text.
    public let modelID: String?
    public let vector: [Float]?

    public init(
        id: UUID = UUID(),
        recordingID: RecordingID,
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        language: String? = nil,
        modelID: String? = nil,
        vector: [Float]? = nil,
    ) {
        self.id = id
        self.recordingID = recordingID
        self.start = start
        self.end = end
        self.text = text
        self.language = language
        self.modelID = modelID
        self.vector = vector
    }
}

/// What the index was built from. Any difference means the chunks are stale.
public struct KnowledgeIndexState: Hashable, Sendable {
    public let sourceHash: String
    public let modelID: String?

    public init(sourceHash: String, modelID: String?) {
        self.sourceHash = sourceHash
        self.modelID = modelID
    }
}

public struct IndexProgress: Hashable, Sendable {
    public let done: Int
    public let total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    public var fraction: Double {
        total == 0 ? 1 : Double(done) / Double(total)
    }
}

/// What a search model's speed test measured.
public struct SearchSpeed: Hashable, Sendable {
    /// About what a minute of a meeting turns into.
    static let sample = """
    We agreed to move the launch to the second week of March, because the payment provider is not ready yet, and \
    Maria will send the updated budget to finance by Friday so that the team can plan the next quarter.
    """
    /// An hour of speech is about 9,000 words, which makes this many passages.
    private static let passagesPerHour = 115.0

    public let modelID: String
    public let passagesPerSecond: Double

    public init(modelID: String, passagesPerSecond: Double) {
        self.modelID = modelID
        self.passagesPerSecond = passagesPerSecond
    }

    public var secondsPerHourOfAudio: Int {
        max(1, Int((Self.passagesPerHour / max(passagesPerSecond, 0.001)).rounded()))
    }
}

public enum AskUpdate: Hashable, Sendable {
    /// Another model is working, and this question is next.
    case waiting
    case searching
    /// The answer so far, without the parts that are not for reading.
    case writing(String)
    case finished(ChatMessage)
}

public enum AskPreferences {
    public static let promptBarKey = "ask.promptBar"

    /// What the prompt bar on a meeting does.
    public enum PromptBar: String, CaseIterable, Sendable {
        case focus, newChat
    }
}

/// Turns text into vectors that sit close together when the meaning is close.
///
/// `embed` loads what it needs, since which model that is depends on the language of the text.
public protocol TextEmbeddingEngine: ModelRunner {
    /// Nil when nothing on the device covers this language right now.
    func modelID(language: String?) async -> String?
    func detectLanguage(of text: String) async -> String?
    /// Returns one unit-length vector per text, all from `modelID(language:)`.
    func embed(_ texts: [String], language: String?) async throws -> [[Float]]
}

public protocol ConversationStore: Sendable {
    /// Most recently used first.
    func conversations() async throws -> [Conversation]
    func save(_ conversation: Conversation) async throws
    func deleteConversation(_ id: UUID) async throws
    func messages(in conversation: UUID) async throws -> [ChatMessage]
    func save(_ message: ChatMessage) async throws

    func memories() async throws -> [MemoryItem]
    func save(_ memory: MemoryItem) async throws
    func deleteMemory(_ id: UUID) async throws
}

public protocol KnowledgeStore: Sendable {
    func indexStates() async throws -> [RecordingID: KnowledgeIndexState]
    /// One transaction, so that a recording is never left half indexed.
    func replaceChunks(_ chunks: [KnowledgeChunk], for id: RecordingID, state: KnowledgeIndexState) async throws
    func removeChunks(for id: RecordingID) async throws
    /// Best first. Recordings in the trash never match.
    func lexicalMatches(terms: [String], scope: AskScope, limit: Int) async throws -> [UUID]
    /// Best first, among chunks from the same model. Recordings in the trash never match.
    func nearest(to vector: [Float], modelID: String, scope: AskScope, limit: Int) async throws -> [UUID]
    func chunks(_ ids: [UUID]) async throws -> [KnowledgeChunk]
}
