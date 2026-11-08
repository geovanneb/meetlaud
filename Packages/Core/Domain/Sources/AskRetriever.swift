import Foundation

/// Finds what a question should read, and where in the audio an answer's claims really are.
struct AskRetriever: Sendable {
    private enum Limits {
        /// How many each search brings in before merging.
        static let candidates = 24
    }

    let knowledge: any KnowledgeStore
    let recordings: any RecordingStore
    let transcripts: any TranscriptStore
    let speakers: any SpeakerStore
    let language: any LanguageModelEngine
    let embedder: any TextEmbeddingEngine
    let indexer: KnowledgeIndexer

    func excerpts(
        for question: String,
        scope: AskScope,
        history: [ChatMessage],
    ) async throws -> [AskExcerpt] {
        if let id = scope.recordingID {
            guard let recording = try await recordings.recording(id), recording.deletedAt == nil else { return [] }
            let segments = try await transcripts.segments(for: id)
            guard !segments.isEmpty else { return [] }
            let people = try await speakers.speakers(for: id)
            let whole = Self.wholeMeeting(segments, speakers: people, title: recording.title)
            if let whole {
                return whole
            }
            // A person can ask about a long meeting the moment it finishes, before the background work gets to it.
            try await indexIfStale(id)
        }
        return try await search(question, scope: scope, history: history)
    }

    private static func wholeMeeting(
        _ segments: [TranscriptSegment],
        speakers: [Speaker],
        title: String,
    ) -> [AskExcerpt]? {
        let excerpts = segments.map { segment in
            AskExcerpt(
                recordingID: segment.recordingID, title: title, time: segment.start,
                text: KnowledgeChunker.speakerLine(segment, speakers: speakers),
            )
        }
        let tokens = excerpts.reduce(0) { $0 + TokenEstimator.tokens(in: $1.text) + 2 }
        return tokens <= AskCoordinator.Limits.contextTokens ? excerpts : nil
    }

    private func indexIfStale(_ id: RecordingID) async throws {
        let state = try await knowledge.indexStates()[id]
        let segments = try await transcripts.segments(for: id)
        let people = try await speakers.speakers(for: id)
        if state?.sourceHash != KnowledgeChunker.sourceHash(segments: segments, speakers: people) {
            await language.unload()
            try await indexer.index(id)
        }
    }

    private func search(_ question: String, scope: AskScope, history: [ChatMessage]) async throws -> [AskExcerpt] {
        // "And who will do it?" only makes sense next to the question before it.
        let previous = history.last { $0.role == .user }?.body ?? ""
        let terms = QueryTerms.terms(in: "\(question) \(previous)")
        var lists = try await [knowledge.lexicalMatches(terms: terms, scope: scope, limit: Limits.candidates)]

        let spoken = await embedder.detectLanguage(of: question)
        if let modelID = await embedder.modelID(language: spoken) {
            // One model at a time, and a warm language model may still be loaded.
            await language.unload()
            let vectors = try await embedder.embed(["\(previous) \(question)"], language: spoken)
            await embedder.unload()
            if let vector = vectors.first {
                try await lists.append(knowledge.nearest(
                    to: vector, modelID: modelID, scope: scope, limit: Limits.candidates,
                ))
            }
        }
        let ids = RankFusion.merge(lists, limit: AskCoordinator.Limits.excerpts)
        let found = try await knowledge.chunks(ids)
        var titles: [RecordingID: String] = [:]
        var result: [AskExcerpt] = []
        for id in ids {
            guard let chunk = found.first(where: { $0.id == id }) else { continue }
            if titles[chunk.recordingID] == nil {
                titles[chunk.recordingID] = try await recordings.recording(chunk.recordingID)?.title
            }
            result.append(AskExcerpt(
                recordingID: chunk.recordingID, title: titles[chunk.recordingID] ?? "",
                time: chunk.start, end: chunk.end, text: chunk.text,
            ))
        }
        return result
    }

    /// A passage lasts about a minute, and the link should land on the phrase that matters.
    func located(
        _ citations: [Citation],
        body: String,
        excerpts: [AskExcerpt],
    ) async throws -> [Citation] {
        var result: [Citation] = []
        for citation in citations {
            guard let end = excerpts.first(where: {
                $0.recordingID == citation.recordingID && $0.time == citation.time && $0.text == citation.excerpt
            })?.end else {
                result.append(citation)
                continue
            }
            let passage = try await transcripts.segments(for: citation.recordingID)
                .filter { $0.start >= citation.time && $0.start < end }
            let people = try await speakers.speakers(for: citation.recordingID)
            let claim = CitationLocator.claim(citing: citation.number, in: body)
            guard let segment = CitationLocator.phrase(for: claim, in: passage) else {
                result.append(citation)
                continue
            }
            result.append(Citation(
                number: citation.number, recordingID: citation.recordingID, recordingTitle: citation.recordingTitle,
                time: segment.start, excerpt: KnowledgeChunker.speakerLine(segment, speakers: people),
            ))
        }
        return result
    }
}
