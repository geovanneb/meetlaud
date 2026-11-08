import Domain
import Foundation

public actor FakeConversationStore: ConversationStore {
    public private(set) var stored: [UUID: Conversation] = [:]
    public private(set) var storedMessages: [ChatMessage] = []
    public private(set) var storedMemories: [MemoryItem] = []

    public init() {}

    public func conversations() -> [Conversation] {
        stored.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func save(_ conversation: Conversation) {
        stored[conversation.id] = conversation
    }

    public func deleteConversation(_ id: UUID) {
        stored[id] = nil
        storedMessages.removeAll { $0.conversationID == id }
    }

    public func messages(in conversation: UUID) -> [ChatMessage] {
        storedMessages.filter { $0.conversationID == conversation }
    }

    public func save(_ message: ChatMessage) {
        storedMessages.removeAll { $0.id == message.id }
        storedMessages.append(message)
    }

    public func memories() -> [MemoryItem] {
        storedMemories
    }

    public func save(_ memory: MemoryItem) {
        storedMemories.removeAll { $0.id == memory.id }
        storedMemories.append(memory)
    }

    public func deleteMemory(_ id: UUID) {
        storedMemories.removeAll { $0.id == id }
    }
}

public actor FakeKnowledgeStore: KnowledgeStore {
    public private(set) var chunksByRecording: [RecordingID: [KnowledgeChunk]] = [:]
    public private(set) var states: [RecordingID: KnowledgeIndexState] = [:]
    public private(set) var replacements = 0
    private let recordings: any RecordingStore

    public init(recordings: any RecordingStore) {
        self.recordings = recordings
    }

    public func indexStates() -> [RecordingID: KnowledgeIndexState] {
        states
    }

    public func replaceChunks(_ chunks: [KnowledgeChunk], for id: RecordingID, state: KnowledgeIndexState) {
        chunksByRecording[id] = chunks
        states[id] = state
        replacements += 1
    }

    public func removeChunks(for id: RecordingID) {
        chunksByRecording[id] = nil
        states[id] = nil
    }

    private func inScope(_ scope: AskScope) async -> [KnowledgeChunk] {
        var result: [KnowledgeChunk] = []
        for (id, chunks) in chunksByRecording {
            guard let recording = try? await recordings.recording(id), recording.deletedAt == nil else { continue }
            switch scope {
            case .library: result += chunks
            case let .folder(folder) where recording.folderID == folder: result += chunks
            case let .recording(wanted) where wanted == id: result += chunks
            default: break
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    public func lexicalMatches(terms: [String], scope: AskScope, limit: Int) async -> [UUID] {
        let scored = await inScope(scope).compactMap { chunk -> (UUID, Int)? in
            let hits = terms.count(where: { chunk.text.localizedCaseInsensitiveContains($0) })
            return hits > 0 ? (chunk.id, hits) : nil
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    public func nearest(to vector: [Float], modelID: String, scope: AskScope, limit: Int) async -> [UUID] {
        let scored = await inScope(scope).compactMap { chunk -> (UUID, Float)? in
            guard chunk.modelID == modelID, let other = chunk.vector else { return nil }
            return (chunk.id, zip(vector, other).reduce(0) { $0 + $1.0 * $1.1 })
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    public func chunks(_ ids: [UUID]) -> [KnowledgeChunk] {
        chunksByRecording.values.flatMap(\.self).filter { ids.contains($0.id) }
    }
}

/// Vectors built from the words themselves, so that the same word lands in the same place, every run.
public actor FakeEmbeddingEngine: TextEmbeddingEngine {
    public private(set) var unloads = 0
    public private(set) var embedded = 0
    public var model: String? = "fake-embedding"

    public init() {}

    public func setModel(_ value: String?) {
        model = value
    }

    public func prepare(model _: ModelDescriptor, folder _: URL?) {}

    public func unload() {
        unloads += 1
    }

    public func modelID(language _: String?) -> String? {
        model
    }

    public func detectLanguage(of _: String) -> String? {
        "en"
    }

    public func embed(_ texts: [String], language _: String?) -> [[Float]] {
        embedded += texts.count
        return texts.map(Self.vector)
    }

    private static func vector(_ text: String) -> [Float] {
        var result = [Float](repeating: 0, count: 64)
        for word in text.lowercased().split(whereSeparator: { !$0.isLetter }) {
            let slot = word.utf8.reduce(7) { ($0 &* 31 &+ Int($1)) & 0xFFFF } % result.count
            result[slot] += 1
        }
        let length = result.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return length == 0 ? result : result.map { $0 / length }
    }
}
