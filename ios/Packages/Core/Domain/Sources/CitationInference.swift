import Foundation

/// Gives each sentence of an answer written without citations the one line it clearly rests on.
enum CitationInference {
    /// At least this many of the sentence's words have to be in the line, and this share of them.
    static let minimumShared = 2
    static let minimumShare = 0.4

    static func cite(_ body: String, excerpts: [AskExcerpt]) -> AnswerParser.Result {
        let lines = excerpts.map { words(in: $0.text) }
        var kept: [String] = []
        var numbering: [Int: Int] = [:]
        var citations: [Citation] = []
        for sentence in sentences(in: body) {
            guard let index = bestLine(for: sentence, lines: lines) else { continue }
            let shown: Int
            if let existing = numbering[index] {
                shown = existing
            } else {
                shown = citations.count + 1
                numbering[index] = shown
                let excerpt = excerpts[index]
                citations.append(Citation(
                    number: shown, recordingID: excerpt.recordingID, recordingTitle: excerpt.title,
                    time: excerpt.time, excerpt: excerpt.text,
                ))
            }
            kept.append(marked(sentence, with: shown))
        }
        guard !citations.isEmpty else { return AnswerParser.Result(body: "", citations: [], hasBasis: false) }
        return AnswerParser.Result(body: kept.joined(separator: " "), citations: citations, hasBasis: true)
    }

    /// The line sharing the most words with the sentence, the earliest when tied. Nil when none is close enough.
    static func bestLine(for sentence: String, lines: [Set<String>]) -> Int? {
        let terms = words(in: sentence)
        guard terms.count >= minimumShared else { return nil }
        var best: (index: Int, shared: Int)?
        for (index, line) in lines.enumerated() {
            let shared = terms.intersection(line).count
            if shared > (best?.shared ?? 0) {
                best = (index, shared)
            }
        }
        guard let best, best.shared >= minimumShared,
              Double(best.shared) / Double(terms.count) >= minimumShare
        else { return nil }
        return best.index
    }

    /// Sentences, with list lines counted as sentences too.
    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            for line in (sentence ?? "").split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    result.append(trimmed)
                }
            }
        }
        return result
    }

    /// The marker goes before the closing punctuation, where the model would have put it.
    static func marked(_ sentence: String, with number: Int) -> String {
        let end = sentence.reversed().prefix { ".!?。！？".contains($0) }.count
        let words = sentence.dropLast(end).trimmingCharacters(in: .whitespaces)
        return "\(words) [\(number)]\(sentence.suffix(end))"
    }

    /// The words that carry meaning. Words like "the" or "que" are in every line, so they prove nothing.
    static func words(in text: String) -> Set<String> {
        Set(QueryTerms.terms(in: text, limit: .max).filter { !stopWords.contains($0) })
    }

    static let stopWords: Set<String> = [
        // English
        "the", "and", "was", "were", "are", "for", "that", "this", "with", "from", "they", "their", "there", "have",
        "has", "had", "but", "not", "you", "what", "which", "who", "about", "also", "will", "would", "been", "into",
        "its", "our", "them", "then", "than", "very", "main", "topic", "meeting", "discussed", "talked", "said",
        // Portuguese
        "que", "não", "uma", "para", "com", "por", "dos", "das", "foi", "são", "sobre", "como", "mais", "isso",
        "essa", "esse", "reunião", "principal", "tema", "assunto",
        // Spanish, without the ones Portuguese already has
        "los", "las", "del", "fue", "más", "eso", "esta", "este", "reunión",
        // Japanese
        "です", "ます", "した", "して", "この", "その", "あの", "こと", "もの", "ため", "会議", "について",
    ]
}
