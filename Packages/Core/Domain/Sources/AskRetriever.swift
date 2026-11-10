import Foundation

/// Finds what a question should read, and where in the audio an answer's claims really are.
struct AskRetriever: Sendable {
    private enum Limits {
        /// How many each search brings in before merging.
        static let candidates = 24
        /// The summary's share of the context. Search results get the rest.
        static let summaryTokens = 600
    }

    let knowledge: any KnowledgeStore
    let recordings: any RecordingStore
    let transcripts: any TranscriptStore
    let speakers: any SpeakerStore
    let summaries: (any SummaryStore)?
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
            // "What was it about?" shares no words with any passage, so search alone finds noise. The summary already
            // answers it, and each of its points is tied to a moment, so a citation still lands on the transcript.
            let overview = try await summaryExcerpts(id, segments: segments, title: recording.title)
            let found = try await search(question, scope: scope, history: history)
            return Self.withinBudget(overview + found)
        }
        return try await search(question, scope: scope, history: history)
    }

    /// The points of the newest summary that are tied to a phrase. A point flagged for review is left out (D-049).
    private func summaryExcerpts(
        _ id: RecordingID,
        segments: [TranscriptSegment],
        title: String,
    ) async throws -> [AskExcerpt] {
        guard let summaries,
              let summary = try await summaries.summaries(for: id).max(by: { $0.createdAt < $1.createdAt })
        else { return [] }
        var result: [AskExcerpt] = []
        var tokens = 0
        for section in summary.sections {
            for item in section.items where !item.needsReview {
                guard let time = item.sourceTime,
                      let segment = segments.last(where: { $0.start <= time }) ?? segments.first
                else { continue }
                let text = "Summary, \(section.title): \(item.text)"
                tokens += TokenEstimator.tokens(in: text) + 2
                guard tokens <= Limits.summaryTokens else { return result }
                // The passage is that one phrase, so the citation shows what was said, not the summary's words.
                result.append(AskExcerpt(
                    recordingID: id, title: title, time: segment.start, end: segment.end, text: text,
                ))
            }
        }
        return result
    }

    /// Keeps the excerpts in order until the context is full.
    private static func withinBudget(_ excerpts: [AskExcerpt]) -> [AskExcerpt] {
        var tokens = 0
        var result: [AskExcerpt] = []
        for excerpt in excerpts {
            tokens += TokenEstimator.tokens(in: excerpt.text) + 2
            guard tokens <= AskCoordinator.Limits.contextTokens else { break }
            result.append(excerpt)
        }
        return result
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
