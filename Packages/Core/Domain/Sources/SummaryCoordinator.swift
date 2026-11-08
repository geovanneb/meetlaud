import Foundation

/// Runs summaries, one at a time, in steps that survive the app closing.
///
/// A language model needs the GPU and a lot of memory, so this is the first thing to give way. It stops when the app
/// leaves the foreground, because Metal work there can crash the app, and when a recording starts, because recording
/// comes first. It picks up from the last saved step.
public actor SummaryCoordinator {
    public enum Limits {
        /// Tokens of transcript or notes per request. Leaves room for instructions and the answer.
        public static let contextTokens = 1500
        /// Runs that end with the app gone. Stopping on purpose does not count.
        public static let attempts = 3
    }

    public typealias ModelResolver = @Sendable (String) -> (model: ModelDescriptor, folder: URL?)?

    private let store: any SummaryStore
    private let transcripts: any TranscriptStore
    private let speakers: any SpeakerStore
    private let engine: any LanguageModelEngine
    private let arbiter: ModelArbiter
    private let models: ModelResolver
    private let canRun: @Sendable () async -> Bool
    private let profile: @Sendable () -> String?

    private var progress: [UUID: SummaryProgress] = [:] {
        didSet { continuation.yield(progress) }
    }

    private var worker: Task<Void, Never>?
    private var running: UUID?
    /// The worker may hold a job it read just before this was canceled, and saving it would bring it back.
    private var canceled: Set<UUID> = []
    private var draft: Task<String, any Error>?
    /// A resume can arrive while the worker is stopping, and must not get lost.
    private var resumeRequested = false

    public nonisolated let updates: AsyncStream<[UUID: SummaryProgress]>
    private let continuation: AsyncStream<[UUID: SummaryProgress]>.Continuation

    public init(
        store: any SummaryStore,
        transcripts: any TranscriptStore,
        speakers: any SpeakerStore,
        engine: any LanguageModelEngine,
        arbiter: ModelArbiter,
        models: @escaping ModelResolver,
        profile: @escaping @Sendable () -> String? = { nil },
        canRun: @escaping @Sendable () async -> Bool = { true },
    ) {
        self.store = store
        self.transcripts = transcripts
        self.speakers = speakers
        self.engine = engine
        self.arbiter = arbiter
        self.models = models
        self.profile = profile
        self.canRun = canRun
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    public var currentProgress: [UUID: SummaryProgress] {
        progress
    }

    // MARK: - Queue

    @discardableResult
    public func enqueue(
        _ id: RecordingID,
        template: SummaryTemplate,
        modelID: String,
        language: String?,
        now: Date = Date(),
    ) async throws -> UUID {
        let summary = Summary(
            recordingID: id, templateName: template.name, modelID: modelID, language: language, createdAt: now,
        )
        try await store.save(summary, job: SummaryJob(
            summaryID: summary.id, recordingID: id, template: template, modelID: modelID, language: language,
        ))
        progress[summary.id] = SummaryProgress(phase: .queued, fraction: 0)
        resume()
        return summary.id
    }

    /// Removes the job and whatever it wrote. The queue goes on with the next one.
    public func cancel(_ id: UUID) async throws {
        canceled.insert(id)
        // A queued job is only rows. Stopping the worker could mean waiting for a long transcription.
        let isRunning = running == id
        if isRunning {
            await suspend()
        }
        try await store.deleteSummaryJob(id)
        try await store.deleteSummary(id)
        progress[id] = nil
        if isRunning {
            resume()
        }
    }

    /// Stops generating right away. Everything already done stays saved.
    public func suspend() async {
        draft?.cancel()
        worker?.cancel()
        await worker?.value
    }

    /// Starts work if there is any and conditions allow it. Safe to call at any time.
    public func resume() {
        guard worker == nil else {
            resumeRequested = true
            return
        }
        worker = Task { [weak self] in
            await self?.drainQueue()
        }
    }

    private func drainQueue() async {
        // Asking for the model when there is nothing to do would make other work wait for no reason.
        let hasWork = await !((try? store.summaryJobs()) ?? []).isEmpty
        // Waiting must stay cancelable: `suspend` waits for this task, and whoever called it may be a person asking
        // something, or a recording that has to start.
        if hasWork, await canRun(), await (try? arbiter.acquireCancelable()) != nil {
            await processJobs()
            await engine.unload()
            await arbiter.release()
        }
        // Cancellation stops database calls too, and this has to happen anyway.
        await Task { await self.markWaiting() }.value
        worker = nil
        if resumeRequested {
            resumeRequested = false
            resume()
        }
    }

    private func processJobs() async {
        do {
            while !Task.isCancelled, let job = try await store.summaryJobs().first {
                try await process(job)
            }
        } catch {
            // Stopped, or the store failed. Either way the jobs stay saved, and the next resume goes on.
        }
    }

    private func process(_ original: SummaryJob) async throws {
        guard !canceled.contains(original.summaryID) else { return }
        guard original.attempts < Limits.attempts else {
            try await abandon(original)
            return
        }
        running = original.summaryID
        defer { running = nil }
        var job = original
        job.attempts += 1
        try await store.save(job)
        do {
            try await run(job)
        } catch {
            // Engines report cancellation in their own way, so the task is what counts.
            guard Task.isCancelled || error is CancellationError else {
                // A failed job would otherwise block the queue forever. What finished stays.
                try await abandon(job)
                return
            }
            await Task { await self.refund(job.summaryID) }.value
            throw CancellationError()
        }
    }

    private func refund(_ id: UUID) async {
        guard var job = await (try? store.summaryJobs())?.first(where: { $0.summaryID == id }) else { return }
        job.attempts -= 1
        try? await store.save(job)
    }

    private func abandon(_ job: SummaryJob) async throws {
        try await store.deleteSummaryJob(job.summaryID)
        progress[job.summaryID] = nil
    }

    private func markWaiting() async {
        for job in await (try? store.summaryJobs()) ?? [] {
            progress[job.summaryID] = SummaryProgress(
                phase: .waiting,
                fraction: progress[job.summaryID]?.fraction ?? 0,
            )
        }
    }
}

// MARK: - Running

extension SummaryCoordinator {
    private func run(_ original: SummaryJob) async throws {
        var job = original
        guard let resolved = models(job.modelID) else { throw TranscriptionError.modelNotInstalled }
        let segments = try await transcripts.segments(for: job.recordingID)
        guard !segments.isEmpty else { throw SummaryError.nothingToSummarize }
        progress[job.summaryID] = SummaryProgress(
            phase: .reading, fraction: progress[job.summaryID]?.fraction ?? 0,
        )
        try await engine.prepare(model: resolved.model, folder: resolved.folder)

        let people = try await speakers.speakers(for: job.recordingID)
        let lines = TranscriptFormatter.lines(segments: segments, speakers: people)
        let spoken = try await transcripts.transcript(for: job.recordingID)?.language
        let language = job.language ?? spoken

        let duration = segments.last?.end ?? 0
        try await prepareNotes(&job, lines: lines, duration: duration, language: language)
        var summary = try await store.summaries(for: job.recordingID).first { $0.id == job.summaryID }
            ?? Summary(
                id: job.summaryID, recordingID: job.recordingID, templateName: job.template.name,
                modelID: job.modelID, language: job.language, createdAt: Date(),
            )

        let total = job.template.sections.count
        while job.nextSection < total {
            let section = job.template.sections[job.nextSection]
            let done = Double(job.nextSection) / Double(total)
            let sameLanguage = job.language == nil || job.language == spoken
            let items = try await sectionItems(
                section, job: job, duration: duration, language: language, showingAs: done,
            )
            .map { SummaryValidator.validate($0, segments: segments, speakers: people, sameLanguage: sameLanguage) }
            .map { Self.tokenized($0, speakers: people) }
            summary.sections.append(SummarySection(title: section.title, kind: section.kind, items: items))
            job.nextSection += 1
            try await store.save(summary, job: job)
            progress[job.summaryID] = SummaryProgress(
                phase: .writing,
                fraction: Double(job.nextSection) / Double(total),
            )
        }

        summary.isComplete = true
        try await store.complete(summary)
        progress[job.summaryID] = nil
    }

    /// A long meeting is read part by part. Given all of it at once, a small model writes mostly about how it ended.
    private func sectionItems(
        _ section: TemplateSection,
        job: SummaryJob,
        duration: TimeInterval,
        language: String?,
        showingAs done: Double,
    ) async throws -> [SummaryItem] {
        let parts = job.nextChunk > 0 ? SummaryParts.split(job.notes, duration: duration) : [job.notes]
        var found: [[SummaryItem]] = []
        for part in parts {
            let request = SummaryPrompts.section(
                section, template: job.template, notes: part, language: language, profile: profile(),
                limit: parts.count > 1 ? SummaryParts.limit(for: section.kind) : nil,
            )
            let text = try await generate(request, showingAs: (job.summaryID, done))
            found.append(SummaryParser.items(from: text, kind: section.kind))
        }
        return found.count > 1 ? SummaryParser.balanced(found, kind: section.kind) : found.first ?? []
    }

    /// A short meeting goes straight to the model, since every summarizing step loses detail.
    private func prepareNotes(
        _ job: inout SummaryJob,
        lines: [String],
        duration: TimeInterval,
        language: String?,
    ) async throws {
        guard job.nextSection == 0 else { return }
        let chunks = TranscriptFormatter.chunks(lines, limit: Limits.contextTokens)
        guard chunks.count > 1 else {
            job.notes = lines
            return
        }
        while job.nextChunk < chunks.count {
            let text = try await generate(SummaryPrompts.notes(lines: chunks[job.nextChunk], language: language))
            job.notes += SummaryParser.notes(from: text)
            job.nextChunk += 1
            try await store.save(job)
            progress[job.summaryID] = SummaryProgress(
                phase: .reading, fraction: Double(job.nextChunk) / Double(chunks.count),
            )
        }
        // Long meetings can leave more notes than fit. Each stretch is condensed on its own: done all at once, this
        // step is where a 3-hour summary lost its first two hours.
        var parts = SummaryParts.split(job.notes, duration: duration)
        for index in parts.indices {
            parts[index] = try await condensed(parts[index], language: language)
            job.notes = Array(parts.joined())
            try await store.save(job)
        }
    }

    private func condensed(_ notes: [String], language: String?) async throws -> [String] {
        var notes = notes
        var rounds = 0
        while rounds < 3, TokenEstimator.tokens(in: notes.joined(separator: "\n")) > Limits.contextTokens {
            var shorter: [String] = []
            for chunk in TranscriptFormatter.chunks(notes, limit: Limits.contextTokens) {
                let text = try await generate(SummaryPrompts.notes(lines: chunk, language: language))
                shorter += SummaryParser.notes(from: text)
            }
            notes = shorter
            rounds += 1
        }
        return notes
    }

    private func generate(
        _ request: LanguageRequest,
        showingAs live: (id: UUID, fraction: Double)? = nil,
    ) async throws -> String {
        // Conditions change between steps, such as the phone getting too hot.
        guard await canRun() else { throw CancellationError() }
        var text = ""
        var chunks = 0
        for try await chunk in engine.generate(request) {
            try Task.checkCancellation()
            text += chunk
            chunks += 1
            // Often enough to read as typing, without redrawing on every token.
            if let live, chunks % 6 == 0 {
                progress[live.id] = SummaryProgress(phase: .writing, fraction: live.fraction, partial: text)
            }
        }
        // A canceled stream ends quietly, and a partial answer must not pass for a finished one.
        try Task.checkCancellation()
        return text
    }

    private static func tokenized(_ item: SummaryItem, speakers: [Speaker]) -> SummaryItem {
        var item = item
        item.text = SpeakerTokens.encode(item.text, speakers: speakers)
        item.owner = item.owner.map { SpeakerTokens.encode($0, speakers: speakers) }
        return item
    }

    // MARK: - Template drafts

    /// Turns a description into a template that a person can edit.
    public func draftTemplate(description: String, modelID: String, language: String?) async throws -> SummaryTemplate {
        guard await canRun(), let resolved = models(modelID) else { throw TemplateError.invalid }
        await suspend()
        await arbiter.acquire()
        let task = Task { [self] in
            try await engine.prepare(model: resolved.model, folder: resolved.folder)
            return try await generate(SummaryPrompts.templateDraft(description: description, language: language))
        }
        draft = task
        let result = await task.result
        draft = nil
        await engine.unload()
        await arbiter.release()
        resume()
        return try TemplateCodec.parseDraft(result.get())
    }
}
