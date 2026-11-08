import Foundation

/// FNV-1a. `Hasher` changes with every launch, and this value has to survive them.
enum StableHash {
    static func hex(_ text: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}

/// Cuts a transcript into stretches that are short enough to embed and specific enough to cite.
public enum KnowledgeChunker {
    /// Embedding models read about 256 tokens, and a shorter stretch keeps the citation close to the moment.
    static let tokenLimit = 120

    public static func chunks(
        segments: [TranscriptSegment],
        speakers: [Speaker],
        language: String?,
    ) -> [KnowledgeChunk] {
        var result: [KnowledgeChunk] = []
        var current: [(segment: TranscriptSegment, line: String)] = []
        var size = 0

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            result.append(KnowledgeChunk(
                recordingID: first.segment.recordingID,
                start: first.segment.start,
                end: last.segment.end,
                text: current.map(\.line).joined(separator: " "),
                language: language,
            ))
        }

        for segment in segments {
            let line = speakerLine(segment, speakers: speakers)
            let tokens = TokenEstimator.tokens(in: line)
            if size + tokens > tokenLimit, !current.isEmpty {
                flush()
                // One phrase of overlap, so that an idea split across two chunks can still be found.
                let overlap = current.suffix(1)
                current = Array(overlap)
                size = overlap.reduce(0) { $0 + TokenEstimator.tokens(in: $1.line) }
            }
            current.append((segment, line))
            size += tokens
        }
        flush()
        return result
    }

    /// Changes when the words, the names, or the order change, which is exactly when the index goes stale.
    public static func sourceHash(segments: [TranscriptSegment], speakers: [Speaker]) -> String {
        StableHash.hex(TranscriptFormatter.lines(segments: segments, speakers: speakers).joined(separator: "\n"))
    }

    static func speakerLine(_ segment: TranscriptSegment, speakers: [Speaker]) -> String {
        let speaker = speakers.first { $0.id.uuidString == segment.speaker }
        return (TranscriptFormatter.displayName(of: speaker).map { "\($0): " } ?? "") + segment.text
    }
}

/// Picks the words of a question worth looking for in the text.
public enum QueryTerms {
    private static let limit = 12

    public static func terms(in text: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, _, _, stop in
            guard let word = word?.lowercased(), isUseful(word), seen.insert(word).inserted else { return }
            result.append(word)
            stop = result.count >= limit
        }
        return result
    }

    /// A two-letter Latin word matches everything. Two Japanese characters are often a whole word.
    private static func isUseful(_ word: String) -> Bool {
        word.count >= 3 || (word.count == 2 && word.unicodeScalars.allSatisfy { $0.value > 0x2E7F })
    }
}

/// Merges ranked lists by position. Scores from different searches cannot be compared, and positions can.
public enum RankFusion {
    private static let damping = 60.0

    public static func merge(_ lists: [[UUID]], limit: Int) -> [UUID] {
        var scores: [UUID: Double] = [:]
        var firstSeen: [UUID: Int] = [:]
        var order = 0
        for list in lists {
            for (rank, id) in list.enumerated() {
                scores[id, default: 0] += 1 / (damping + Double(rank + 1))
                if firstSeen[id] == nil {
                    firstSeen[id] = order
                    order += 1
                }
            }
        }
        let ranked = scores.keys.sorted { lhs, rhs in
            let left = scores[lhs] ?? 0
            let right = scores[rhs] ?? 0
            return left == right ? (firstSeen[lhs] ?? 0) < (firstSeen[rhs] ?? 0) : left > right
        }
        return Array(ranked.prefix(limit))
    }
}

/// A numbered piece of text the model may quote.
public struct AskExcerpt: Hashable, Sendable {
    public let recordingID: RecordingID
    public let title: String
    public let time: TimeInterval
    /// Set when this is a passage, with several phrases inside. Nil when it is one exact phrase.
    public let end: TimeInterval?
    public let text: String

    public init(recordingID: RecordingID, title: String, time: TimeInterval, end: TimeInterval? = nil, text: String) {
        self.recordingID = recordingID
        self.title = title
        self.time = time
        self.end = end
        self.text = text
    }
}

/// Finds the phrase inside a passage that a statement rests on.
public enum CitationLocator {
    /// The sentence that ends with this citation.
    public static func claim(citing number: Int, in body: String) -> String {
        guard let marker = body.range(of: "[\(number)]") else { return "" }
        let before = body[..<marker.lowerBound]
        let start = before.lastIndex { ".!?。！？\n".contains($0) }
        return String(start.map { before[before.index(after: $0)...] } ?? before)
    }

    /// The phrase sharing the most words with the claim, the earliest when tied. Nil with nothing to choose from.
    public static func phrase(for claim: String, in passage: [TranscriptSegment]) -> TranscriptSegment? {
        let terms = QueryTerms.terms(in: claim)
        var best = passage.first
        var bestScore = 0
        for segment in passage {
            let score = terms.count(where: { segment.text.localizedCaseInsensitiveContains($0) })
            if score > bestScore {
                best = segment
                bestScore = score
            }
        }
        return best
    }
}

/// Recognizes "remember that…", so that saving a fact never depends on a model's reading of it.
public enum MemoryCommand {
    private static let prefixes = [
        "remember that ", "please remember that ", "remember ", "please remember ",
        "lembre-se de que ", "lembre-se que ", "lembre que ", "lembra que ", "lembre-se ", "lembre ",
        "recuerda que ", "recuerde que ", "recuerda ",
    ]
    private static let suffixes = ["と覚えておいて", "を覚えておいて", "と覚えて", "を覚えて"]

    public static func text(in question: String) -> String? {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        // "Do you remember what Ana said?" is a question for the meetings, not a request to save something.
        guard !trimmed.hasSuffix("?"), !trimmed.hasSuffix("？") else { return nil }
        let unpunctuated = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ".。!！ "))
        let lowered = unpunctuated.lowercased()
        for prefix in prefixes where lowered.hasPrefix(prefix) {
            return nonEmpty(String(unpunctuated.dropFirst(prefix.count)))
        }
        for suffix in suffixes where unpunctuated.hasSuffix(suffix) {
            return nonEmpty(String(unpunctuated.dropLast(suffix.count)))
        }
        return nil
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum AskPrompts {
    static let notFound = "NOT_FOUND"
    private static let excerptSize = 280
    private static let historyTurns = 4
    private static let historySize = 300

    public static func answer(
        question: String,
        excerpts: [AskExcerpt],
        history: [ChatMessage],
        memories: [MemoryItem],
        profile: String?,
        skill: String? = nil,
    ) -> LanguageRequest {
        let multipleSources = Set(excerpts.map(\.recordingID)).count > 1
        let text = excerpts.enumerated().map { index, excerpt in
            let source = multipleSources ? "(\(excerpt.title)) " : ""
            return "[\(index + 1)] \(source)\(excerpt.text)"
        }
        let earlier = history.suffix(historyTurns)
            .filter { !$0.body.isEmpty }
            .map { "\($0.role == .user ? "Person" : "You"): \($0.body.prefix(historySize))" }
        let conversation = earlier.isEmpty ? "" : "Earlier in this chat:\n\(earlier.joined(separator: "\n"))\n\n"

        var about = ""
        if let profile {
            about += "\nAbout the reader: \(profile.prefix(SummaryPreferences.profileLimit))"
        }
        if !memories.isEmpty {
            about += "\nThe reader asked you to keep in mind: \(memories.map(\.text).joined(separator: "; "))"
        }
        if let skill {
            // After the rules on sources, so that it can shape an answer and never change where the answer comes from.
            about += "\nShape your answer this way: \(skill.prefix(Skill.instructionsLimit))"
        }
        return LanguageRequest(
            system: """
            You answer questions about recorded meetings, using only the numbered lines between <transcript> tags.
            After every statement, write the number of the line that supports it, like this: [2]
            If those lines do not answer the question, write exactly \(notFound) and nothing else. Never guess, and \
            never use anything you know from elsewhere. Be brief. Answer in the language of the question.\(about)
            \(SummaryPrompts.safety)
            """,
            prompt: """
            <transcript>
            \(text.joined(separator: "\n"))
            </transcript>

            \(conversation)Question: \(question)
            """,
            maxTokens: 400,
        )
    }
}

/// Reads an answer, and keeps only the citations that are real. See D-049.
public enum AnswerParser {
    public struct Result: Equatable, Sendable {
        public let body: String
        public let citations: [Citation]
        public let hasBasis: Bool
    }

    private nonisolated(unsafe) static let reference = /\[\s*(\d+(?:\s*[,、]\s*\d+)*)\s*\]/

    public static func parse(_ text: String, excerpts: [AskExcerpt]) -> Result {
        guard !text.contains(AskPrompts.notFound) else { return Result(body: "", citations: [], hasBasis: false) }

        var numbering: [Int: Int] = [:]
        var citations: [Citation] = []
        let body = text.replacing(reference) { match in
            let numbers = match.output.1
                .split(whereSeparator: { ",、 ".contains($0) })
                .compactMap { Int($0) }
            return numbers.compactMap { number -> String? in
                guard excerpts.indices.contains(number - 1) else { return nil }
                if let existing = numbering[number] {
                    return "[\(existing)]"
                }
                let excerpt = excerpts[number - 1]
                let shown = citations.count + 1
                numbering[number] = shown
                citations.append(Citation(
                    number: shown, recordingID: excerpt.recordingID, recordingTitle: excerpt.title,
                    time: excerpt.time, excerpt: excerpt.text,
                ))
                return "[\(shown)]"
            }
            .joined()
        }
        .trimmingCharacters(in: .whitespacesAndNewlines)

        // An answer with nothing behind it reads exactly like a good one, so it does not get shown.
        guard !citations.isEmpty else { return Result(body: "", citations: [], hasBasis: false) }
        return Result(body: body, citations: citations, hasBasis: true)
    }

    /// What can be shown while the model writes. The refusal word starts arriving before it can be recognized.
    public static func visible(_ partial: String) -> String {
        let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(AskPrompts.notFound) || AskPrompts.notFound.hasPrefix(trimmed) {
            return ""
        }
        return trimmed
    }
}
