import Domain
import Foundation
import GRDB
@testable import Persistence
import Testing

struct AskDatabaseTests {
    private func store() throws -> DatabaseStore {
        try DatabaseStore(database: DatabaseQueue())
    }

    private func recording(
        _ store: DatabaseStore,
        title: String = "Sync",
        folder: FolderID? = nil,
    ) async throws -> Recording {
        let recording = Recording(title: title, createdAt: .now, folderID: folder)
        try await store.insert(recording)
        return recording
    }

    private func chunk(
        _ id: RecordingID,
        _ text: String,
        vector: [Float]? = nil,
        model: String? = "m",
    ) -> KnowledgeChunk {
        KnowledgeChunk(recordingID: id, start: 5, end: 9, text: text, language: "en", modelID: model, vector: vector)
    }

    private let state = KnowledgeIndexState(sourceHash: "abc", modelID: "m")

    @Test func `a conversation and its messages round-trip, citations included`() async throws {
        let store = try store()
        let meeting = try await recording(store)
        let conversation = Conversation(title: "Q", scope: .recording(meeting.id), createdAt: .now)
        try await store.save(conversation)
        let citation = Citation(number: 1, recordingID: meeting.id, recordingTitle: "Sync", time: 4, excerpt: "Hi")
        let answer = ChatMessage(
            conversationID: conversation.id, role: .assistant, body: "Yes [1]", citations: [citation], createdAt: .now,
        )
        try await store.save(answer)

        #expect(try await store.conversations().map(\.scope) == [.recording(meeting.id)])
        #expect(try await store.messages(in: conversation.id).first?.citations == [citation])
    }

    @Test func `the question comes before an answer saved at the same moment`() async throws {
        let store = try store()
        let conversation = Conversation(scope: .library, createdAt: .now)
        try await store.save(conversation)
        let now = Date()
        try await store.save(ChatMessage(conversationID: conversation.id, role: .assistant, body: "A", createdAt: now))
        try await store.save(ChatMessage(conversationID: conversation.id, role: .user, body: "Q", createdAt: now))
        #expect(try await store.messages(in: conversation.id).map(\.role) == [.user, .assistant])
    }

    @Test func `renaming a conversation keeps its messages`() async throws {
        let store = try store()
        var conversation = Conversation(scope: .library, createdAt: .now)
        try await store.save(conversation)
        try await store.save(ChatMessage(conversationID: conversation.id, role: .user, body: "Q", createdAt: .now))
        conversation.title = "New name"
        try await store.save(conversation)
        #expect(try await store.messages(in: conversation.id).count == 1)
        #expect(try await store.conversations().first?.title == "New name")
    }

    @Test func `deleting a conversation takes its messages`() async throws {
        let store = try store()
        let conversation = Conversation(scope: .library, createdAt: .now)
        try await store.save(conversation)
        try await store.save(ChatMessage(conversationID: conversation.id, role: .user, body: "Q", createdAt: .now))
        try await store.deleteConversation(conversation.id)
        #expect(try await store.messages(in: conversation.id).isEmpty)
    }

    @Test func `deleting a recording leaves none of its words behind`() async throws {
        let store = try store()
        let meeting = try await recording(store)
        let other = try await recording(store, title: "Other")
        try await store.replaceChunks([chunk(meeting.id, "secret words")], for: meeting.id, state: state)

        let scoped = Conversation(scope: .recording(meeting.id), createdAt: .now)
        let library = Conversation(scope: .library, createdAt: .now)
        try await store.save(scoped)
        try await store.save(library)
        let quoting = Citation(
            number: 1, recordingID: meeting.id, recordingTitle: "Sync", time: 0, excerpt: "secret words",
        )
        let safe = Citation(number: 1, recordingID: other.id, recordingTitle: "Other", time: 0, excerpt: "fine")
        try await store.save(ChatMessage(
            conversationID: library.id, role: .assistant, body: "secret", citations: [quoting], createdAt: .now,
        ))
        try await store.save(ChatMessage(
            conversationID: library.id, role: .assistant, body: "fine", citations: [safe], createdAt: .now,
        ))

        try await store.delete(meeting.id)

        #expect(try await store.lexicalMatches(terms: ["secret"], scope: .library, limit: 5).isEmpty)
        #expect(try await store.indexStates().isEmpty)
        #expect(try await store.conversations().map(\.id) == [library.id])
        #expect(try await store.messages(in: library.id).map(\.body) == ["fine"])
    }

    @Test func `memories can be added and removed`() async throws {
        let store = try store()
        let memory = MemoryItem(text: "Ana leads sales", createdAt: .now)
        try await store.save(memory)
        #expect(try await store.memories().map(\.text) == ["Ana leads sales"])
        try await store.deleteMemory(memory.id)
        #expect(try await store.memories().isEmpty)
    }

    @Test func `chunks round-trip, vector included, and replacing swaps them all`() async throws {
        let store = try store()
        let meeting = try await recording(store)
        let first = chunk(meeting.id, "first text", vector: [0.25, -0.5])
        try await store.replaceChunks([first], for: meeting.id, state: state)
        #expect(try await store.chunks([first.id]) == [first])

        let second = chunk(meeting.id, "second text")
        try await store.replaceChunks([second], for: meeting.id, state: state)
        #expect(try await store.chunks([first.id]).isEmpty)
        #expect(try await store.lexicalMatches(terms: ["first"], scope: .library, limit: 5).isEmpty)
        #expect(try await store.lexicalMatches(terms: ["second"], scope: .library, limit: 5) == [second.id])
        #expect(try await store.indexStates()[meeting.id] == state)
    }

    @Test func `word search finds Japanese, long and short, and any of several terms`() async throws {
        let store = try store()
        let meeting = try await recording(store)
        let japanese = chunk(meeting.id, "来年の出張予算は半分に削減されました")
        let english = chunk(meeting.id, "The launch moved to March")
        try await store.replaceChunks([japanese, english], for: meeting.id, state: state)

        #expect(try await store.lexicalMatches(terms: ["出張予算"], scope: .library, limit: 5) == [japanese.id])
        #expect(try await store.lexicalMatches(terms: ["予算"], scope: .library, limit: 5) == [japanese.id])
        #expect(try await store.lexicalMatches(terms: ["launch", "zzzz"], scope: .library, limit: 5) == [english.id])
    }

    @Test func `odd characters in a question cannot break the search`() async throws {
        let store = try store()
        let meeting = try await recording(store)
        try await store.replaceChunks([chunk(meeting.id, "plain text")], for: meeting.id, state: state)
        for term in ["a\"b OR c", "NEAR(", "100%", "*", "\"\""] {
            _ = try await store.lexicalMatches(terms: [term], scope: .library, limit: 5)
        }
    }

    @Test func `search respects scope and the trash`() async throws {
        let store = try store()
        let folder = Folder(name: "Clients", createdAt: .now)
        try await store.insert(folder)
        let inside = try await recording(store, folder: folder.id)
        var trashed = try await recording(store)
        let outside = try await recording(store)
        let insideChunk = chunk(inside.id, "zebra inside", vector: [1, 0])
        let trashedChunk = chunk(trashed.id, "zebra trashed", vector: [1, 0])
        let outsideChunk = chunk(outside.id, "zebra outside", vector: [1, 0])
        try await store.replaceChunks([insideChunk], for: inside.id, state: state)
        try await store.replaceChunks([trashedChunk], for: trashed.id, state: state)
        try await store.replaceChunks([outsideChunk], for: outside.id, state: state)
        trashed.deletedAt = .now
        try await store.update(trashed)

        let words = try await store.lexicalMatches(terms: ["zebra"], scope: .library, limit: 5)
        #expect(Set(words) == [insideChunk.id, outsideChunk.id])
        let vectors = try await store.nearest(to: [1, 0], modelID: "m", scope: .library, limit: 5)
        #expect(Set(vectors) == [insideChunk.id, outsideChunk.id])

        for scope in [AskScope.folder(folder.id), .recording(inside.id)] {
            #expect(try await store.lexicalMatches(terms: ["zebra"], scope: scope, limit: 5) == [insideChunk.id])
            #expect(try await store.nearest(to: [1, 0], modelID: "m", scope: scope, limit: 5) == [insideChunk.id])
        }
    }

    @Test func `the nearest vectors come first, and the limit holds`() async throws {
        let store = try store()
        let meeting = try await recording(store)
        let close = chunk(meeting.id, "a", vector: [1, 0])
        let middle = chunk(meeting.id, "b", vector: [0.7, 0.7])
        let far = chunk(meeting.id, "c", vector: [0, 1])
        try await store.replaceChunks([far, close, middle], for: meeting.id, state: state)
        #expect(try await store.nearest(to: [1, 0], modelID: "m", scope: .library, limit: 2) == [close.id, middle.id])
    }

    @Test func `vectors from another model or of another size never compare`() async throws {
        let store = try store()
        let meeting = try await recording(store)
        try await store.replaceChunks([
            chunk(meeting.id, "other model", vector: [1, 0], model: "other"),
            chunk(meeting.id, "wrong size", vector: [1, 0, 0]),
            chunk(meeting.id, "no vector"),
        ], for: meeting.id, state: state)
        #expect(try await store.nearest(to: [1, 0], modelID: "m", scope: .library, limit: 5).isEmpty)
    }

    @Test func `v5 data survives the v6 migration`() async throws {
        let queue = try DatabaseQueue()
        try DatabaseStore.migrator.migrate(queue, upTo: "v5-summaries")
        let id = RecordingID()
        try await queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO recording (id, title, createdAt, duration, status, wasRecovered, attendees)
                VALUES (?, 'Old', ?, 5, 'ready', 0, '[]')
                """,
                arguments: [id.rawValue.uuidString, Date()],
            )
        }
        let store = try DatabaseStore(database: queue)
        #expect(try await store.recording(id)?.title == "Old")
        #expect(try await store.conversations().isEmpty)
        #expect(try await store.indexStates().isEmpty)
    }
}
