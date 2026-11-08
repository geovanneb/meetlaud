import Foundation

/// Keeps the search index in step with the transcripts, a little at a time.
///
/// It compares what each transcript looks like now against what was indexed, so edits, renamed speakers, retranscribed
/// meetings, and an OS update that replaces the model are all the same case. There is nothing to invalidate by hand.
public actor KnowledgeIndexer {
    private let recordings: any RecordingStore
    private let transcripts: any TranscriptStore
    private let speakers: any SpeakerStore
    private let knowledge: any KnowledgeStore
    private let engine: any TextEmbeddingEngine
    private let arbiter: ModelArbiter
    private let canRun: @Sendable () async -> Bool

    private var worker: Task<Void, Never>?
    private var runRequested = false

    public nonisolated let updates: AsyncStream<IndexProgress?>
    private let continuation: AsyncStream<IndexProgress?>.Continuation

    public init(
        recordings: any RecordingStore,
        transcripts: any TranscriptStore,
        speakers: any SpeakerStore,
        knowledge: any KnowledgeStore,
        engine: any TextEmbeddingEngine,
        arbiter: ModelArbiter,
        canRun: @escaping @Sendable () async -> Bool = { true },
    ) {
        self.recordings = recordings
        self.transcripts = transcripts
        self.speakers = speakers
        self.knowledge = knowledge
        self.engine = engine
        self.arbiter = arbiter
        self.canRun = canRun
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Starts indexing if anything changed. Safe to call at any time.
    public func run() {
        guard worker == nil else {
            runRequested = true
            return
        }
        worker = Task { [weak self] in
            await self?.work()
        }
    }

    /// Stops after the current batch of text. The next run goes on from there.
    public func suspend() async {
        worker?.cancel()
        await worker?.value
    }

    public var isRunning: Bool {
        worker != nil
    }

    private func work() async {
        do {
            let pending = try await staleRecordings()
            for (done, id) in pending.enumerated() {
                continuation.yield(IndexProgress(done: done, total: pending.count))
                guard await canRun() else { break }
                // One recording per turn, so that a person asking something never waits for the whole library.
                try await arbiter.acquireCancelable(checkingEvery: .seconds(1))
                do {
                    try await index(id)
                } catch {
                    guard !Task.isCancelled else {
                        await handBack()
                        throw error
                    }
                    // A recording that was deleted a moment ago must not stop the others.
                }
                await handBack()
            }
        } catch {
            // Stopped, or the store failed. Nothing is half written, and the next run finds what is left.
        }
        continuation.yield(nil)
        worker = nil
        if runRequested {
            runRequested = false
            run()
        }
    }

    private func handBack() async {
        await Task {
            await engine.unload()
            await arbiter.release()
        }.value
    }

    private func staleRecordings() async throws -> [RecordingID] {
        let states = try await knowledge.indexStates()
        var stale: [RecordingID] = []
        for recording in try await recordings.recordings(status: .ready) where recording.deletedAt == nil {
            if try await needsIndexing(recording.id, indexed: states[recording.id]) {
                stale.append(recording.id)
            }
        }
        return stale
    }

    private func needsIndexing(_ id: RecordingID, indexed: KnowledgeIndexState?) async throws -> Bool {
        guard let transcript = try await transcripts.transcript(for: id), transcript.isComplete else {
            // The transcript was removed, and its text must not stay findable.
            return indexed != nil
        }
        let segments = try await transcripts.segments(for: id)
        let people = try await speakers.speakers(for: id)
        guard let indexed else { return !segments.isEmpty }
        let language = try await language(of: id, segments: segments)
        return await indexed != KnowledgeIndexState(
            sourceHash: KnowledgeChunker.sourceHash(segments: segments, speakers: people),
            modelID: engine.modelID(language: language),
        )
    }

    private func language(of id: RecordingID, segments: [TranscriptSegment]) async throws -> String? {
        if let language = try await transcripts.transcript(for: id)?.language {
            return language
        }
        let sample = segments.prefix(20).map(\.text).joined(separator: " ")
        return await engine.detectLanguage(of: sample)
    }

    /// Rebuilds one recording. The caller holds the arbiter.
    func index(_ id: RecordingID) async throws {
        guard let transcript = try await transcripts.transcript(for: id), transcript.isComplete else {
            try await knowledge.removeChunks(for: id)
            return
        }
        let segments = try await transcripts.segments(for: id)
        let people = try await speakers.speakers(for: id)
        let language = try await language(of: id, segments: segments)
        var chunks = KnowledgeChunker.chunks(segments: segments, speakers: people, language: language)
        let modelID = await engine.modelID(language: language)
        if let modelID {
            chunks = try await embedded(chunks, language: language, modelID: modelID)
        }
        // Without a model the chunks still go in, because search by words works with no model at all.
        try await knowledge.replaceChunks(chunks, for: id, state: KnowledgeIndexState(
            sourceHash: KnowledgeChunker.sourceHash(segments: segments, speakers: people),
            modelID: modelID,
        ))
    }

    private func embedded(
        _ chunks: [KnowledgeChunk],
        language: String?,
        modelID: String,
    ) async throws -> [KnowledgeChunk] {
        var result: [KnowledgeChunk] = []
        result.reserveCapacity(chunks.count)
        // Batches are the points where it can stop, or let the phone breathe.
        for start in stride(from: 0, to: chunks.count, by: 16) {
            try Task.checkCancellation()
            let batch = Array(chunks[start ..< min(start + 16, chunks.count)])
            let vectors = try await engine.embed(batch.map(\.text), language: language)
            for (chunk, vector) in zip(batch, vectors) {
                result.append(KnowledgeChunk(
                    id: chunk.id, recordingID: chunk.recordingID, start: chunk.start, end: chunk.end,
                    text: chunk.text, language: language, modelID: modelID, vector: vector,
                ))
            }
        }
        return result
    }
}
