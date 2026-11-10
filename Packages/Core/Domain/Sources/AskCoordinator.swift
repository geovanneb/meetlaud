import Foundation

/// Answers one question at a time, from what is in the recordings and nothing else.
///
/// A short meeting goes to the model whole, for the same reason as in D-046. Anything bigger goes through search: words
/// and meaning together, because each finds what the other misses. For one meeting, the summary's points that are tied
/// to
/// a moment come first, since a question like "what was it about?" shares no words with any passage. Similarity alone
/// cannot say that nothing matches
/// (see SP-5), so the refusal comes from the model and from checking its citations.
public actor AskCoordinator {
    public enum Limits {
        /// Tokens of excerpts per question. Leaves room for instructions, history, and the answer.
        public static let contextTokens = 1500
        public static let excerpts = 8
        /// How long the model stays loaded after an answer. Follow-ups come quickly, and loading takes seconds.
        public static let keepWarm: Duration = .seconds(45)
    }

    public typealias ModelResolver = @Sendable (String) -> (model: ModelDescriptor, folder: URL?)?

    private let conversations: any ConversationStore
    private let retriever: AskRetriever
    private let language: any LanguageModelEngine
    private let embedder: any TextEmbeddingEngine
    private let arbiter: ModelArbiter
    private let models: ModelResolver
    private let profile: @Sendable () -> String?
    private let canRun: @Sendable () async -> Bool
    /// Summaries run for minutes, and a person waiting for an answer comes first.
    private let pauseOtherWork: @Sendable () async -> Void
    private let resumeOtherWork: @Sendable () async -> Void

    private var current: Task<Void, Never>?
    /// The turn is still ours and the model is still loaded, ready for the next question.
    private var isWarm = false
    private var warmTimer: Task<Void, Never>?
    private let keepWarm: Duration

    public init(
        conversations: any ConversationStore,
        knowledge: any KnowledgeStore,
        recordings: any RecordingStore,
        transcripts: any TranscriptStore,
        speakers: any SpeakerStore,
        summaries: (any SummaryStore)? = nil,
        language: any LanguageModelEngine,
        embedder: any TextEmbeddingEngine,
        indexer: KnowledgeIndexer,
        arbiter: ModelArbiter,
        models: @escaping ModelResolver,
        profile: @escaping @Sendable () -> String? = { nil },
        canRun: @escaping @Sendable () async -> Bool = { true },
        pauseOtherWork: @escaping @Sendable () async -> Void = {},
        resumeOtherWork: @escaping @Sendable () async -> Void = {},
        keepWarm: Duration = Limits.keepWarm,
    ) {
        self.conversations = conversations
        retriever = AskRetriever(
            knowledge: knowledge, recordings: recordings, transcripts: transcripts, speakers: speakers,
            summaries: summaries, language: language, embedder: embedder, indexer: indexer,
        )
        self.language = language
        self.embedder = embedder
        self.arbiter = arbiter
        self.models = models
        self.profile = profile
        self.canRun = canRun
        self.pauseOtherWork = pauseOtherWork
        self.resumeOtherWork = resumeOtherWork
        self.keepWarm = keepWarm
    }

    /// Saves the question first, so that nothing the person typed gets lost. A new question stops the previous answer.
    public func ask(
        _ question: String,
        in conversation: Conversation,
        modelID: String?,
        skill: String? = nil,
        now: Date = Date(),
    ) async -> AsyncStream<AskUpdate> {
        await stop()
        let (stream, continuation) = AsyncStream.makeStream(of: AskUpdate.self)
        let task = Task { [self] in
            let reply = await reply(to: question, in: conversation, modelID: modelID, skill: skill, now: now) {
                continuation.yield($0)
            }
            continuation.yield(.finished(reply))
            continuation.finish()
        }
        current = task
        return stream
    }

    /// Ends the answer. What was already written stays, marked as stopped.
    public func stop() async {
        current?.cancel()
        await current?.value
        current = nil
    }

    /// Ends the answer and frees the model now. For leaving the foreground, and for a recording about to start.
    public func stopAndRelease() async {
        await stop()
        await releaseWarmModel()
    }

    public var holdsWarmModel: Bool {
        isWarm
    }

    private func releaseWarmModel() async {
        warmTimer?.cancel()
        warmTimer = nil
        guard isWarm else { return }
        isWarm = false
        await release(true)
    }

    private func stayWarm() {
        isWarm = true
        warmTimer?.cancel()
        let delay = keepWarm
        warmTimer = Task { [weak self] in
            guard await (try? Task.sleep(for: delay)) != nil else { return }
            await self?.releaseWarmModel()
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func reply(
        to question: String,
        in original: Conversation,
        modelID: String?,
        skill: String?,
        now: Date,
        update: @Sendable (AskUpdate) -> Void,
    ) async -> ChatMessage {
        var conversation = original
        conversation.updatedAt = now
        if conversation.title.isEmpty {
            conversation.title = String(question.prefix(60))
        }
        let history = await (try? conversations.messages(in: conversation.id)) ?? []
        let asked = ChatMessage(conversationID: conversation.id, role: .user, body: question, createdAt: now)
        await persist(conversation, asked)

        var message = ChatMessage(
            conversationID: conversation.id, role: .assistant, body: "", state: .failed, createdAt: now,
        )
        if let fact = MemoryCommand.text(in: question) {
            try? await conversations.save(MemoryItem(text: fact, createdAt: now))
            message.body = fact
            message.state = .remembered
        } else if let modelID, let resolved = models(modelID) {
            let turn = Turn(
                question: question, conversation: conversation, history: history, model: resolved, skill: skill,
            )
            await answer(turn, into: &message, update: update)
        }
        await persist(nil, message)
        return message
    }

    /// Cancellation stops database calls too, and these saves have to happen anyway.
    private func persist(_ conversation: Conversation?, _ message: ChatMessage) async {
        await Task { [conversations] in
            if let conversation {
                try? await conversations.save(conversation)
            }
            try? await conversations.save(message)
        }.value
    }

    private struct Turn {
        let question: String
        let conversation: Conversation
        let history: [ChatMessage]
        let model: (model: ModelDescriptor, folder: URL?)
        let skill: String?
    }

    private func answer(
        _ turn: Turn,
        into message: inout ChatMessage,
        update: @Sendable (AskUpdate) -> Void,
    ) async {
        var written = ""
        var excerpts: [AskExcerpt] = []
        // A warm model keeps the turn from the last answer, and other work is already paused.
        var holdsModel = isWarm
        do {
            try await takeTurn(update: update)
            holdsModel = true
            update(.searching)
            excerpts = try await retriever.excerpts(
                for: turn.question,
                scope: turn.conversation.scope,
                history: turn.history,
            )
            guard !excerpts.isEmpty else {
                message.state = .noBasis
                await release(holdsModel)
                return
            }
            try await language.prepare(model: turn.model.model, folder: turn.model.folder)
            let request = try await AskPrompts.answer(
                question: turn.question, excerpts: excerpts, history: turn.history,
                memories: conversations.memories(), profile: profile(), skill: turn.skill,
            )
            guard await canRun() else { throw CancellationError() }
            for try await chunk in language.generate(request) {
                try Task.checkCancellation()
                written += chunk
                update(.writing(AnswerParser.visible(written)))
            }
            try Task.checkCancellation()
            let result = AnswerParser.parse(written, excerpts: excerpts)
            message.body = result.body
            // A citation at the start of its passage still works, so this can never cost the answer.
            let located = try? await retriever.located(result.citations, body: result.body, excerpts: excerpts)
            message.citations = located ?? result.citations
            message.state = result.hasBasis ? .complete : .noBasis
            stayWarm()
            return
        } catch {
            // Engines report cancellation in their own way, so the task is what counts.
            if Task.isCancelled || error is CancellationError {
                let result = AnswerParser.parse(written, excerpts: excerpts)
                message.body = result.hasBasis ? result.body : AnswerParser.visible(written)
                message.citations = result.citations
                message.state = .stopped
            }
        }
        await release(holdsModel)
    }

    /// Gets the right to use the model, unless the last answer left it warm.
    private func takeTurn(update: @Sendable (AskUpdate) -> Void) async throws {
        let wasWarm = isWarm
        warmTimer?.cancel()
        isWarm = false
        if !wasWarm {
            await pauseOtherWork()
        }
        guard await canRun() else { throw CancellationError() }
        if !wasWarm, await !arbiter.tryAcquire() {
            update(.waiting)
            try await arbiter.acquireCancelable()
        }
    }

    private func release(_ holdsModel: Bool) async {
        await Task { [language, embedder, arbiter, resumeOtherWork] in
            if holdsModel {
                await language.unload()
                await embedder.unload()
                await arbiter.release()
            }
            await resumeOtherWork()
        }.value
    }
}
