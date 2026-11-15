import Foundation

/// The languages of one summary. Any of them can be unknown.
struct SummaryLanguages {
    /// What the transcript is in.
    let spoken: String?
    /// What the person picked, or nil for the same as spoken.
    let asked: String?

    /// What the model writes the sections in.
    var written: String? {
        spoken ?? asked
    }

    /// What the reader gets.
    var target: String? {
        asked ?? spoken
    }
}

// MARK: - Translating

extension SummaryCoordinator {
    /// Brings every item into the language the person asked for: all of them when the summary was written in another
    /// language, and otherwise only those the model let slip into one.
    func inLanguage(
        _ items: [SummaryItem],
        kind: SectionKind,
        languages: SummaryLanguages,
        names: [String],
    ) async throws -> [SummaryItem] {
        guard let target = languages.target else { return items }
        let needed = items.indices.filter {
            languages.written != target || LanguageCheck.isWrong(items[$0].text, for: target)
        }
        guard !needed.isEmpty else { return items }
        var result = items
        var missing: [Int] = []
        let batch = try await translations(of: needed.map { items[$0] }, kind: kind, into: target, names: names)
        if batch.count == needed.count {
            for (index, item) in zip(needed, batch) {
                if LanguageCheck.isWrong(item.text, for: target) {
                    missing.append(index)
                } else {
                    result[index] = Self.translated(items[index], to: item, kind: kind)
                }
            }
        } else {
            // A model that merged or dropped a line would pair translations with the wrong citations.
            missing = needed
        }
        for index in missing {
            if let item = try await translations(of: [items[index]], kind: kind, into: target, names: names).first,
               !LanguageCheck.isWrong(item.text, for: target)
            {
                result[index] = Self.translated(items[index], to: item, kind: kind)
            }
            // One that still fails stays as it was: a point in the wrong language is better than a missing one.
        }
        return result
    }

    private func translations(
        of items: [SummaryItem],
        kind: SectionKind,
        into language: String,
        names: [String],
    ) async throws -> [SummaryItem] {
        let lines = items.map { SummaryParser.line(for: $0, kind: kind) }
        let text = try await generate(SummaryPrompts.translation(lines, into: language, names: names))
        return text.split(whereSeparator: \.isNewline)
            .compactMap { SummaryParser.items(from: String($0), kind: kind).first }
    }

    /// The words change. The citation, the owner, and whether it needs review stay those of the original.
    private static func translated(_ original: SummaryItem, to translation: SummaryItem, kind: SectionKind)
        -> SummaryItem
    {
        var item = original
        item.text = translation.text
        if kind == .tasks, original.due != nil {
            item.due = translation.due ?? original.due
        }
        return item
    }

    /// Names the translation keeps as they are. Japanese text can hold a name in Latin letters, but a name in kanji
    /// has to be romanized for English, Portuguese, or Spanish, and asking to keep it made the model keep the line.
    static func keptNames(_ speakers: [Speaker], in language: String?) -> [String] {
        let names = speakers.compactMap(TranscriptFormatter.displayName(of:))
        guard let language, language != "ja" else { return names }
        return names.filter { !LanguageCheck.isWrong($0, for: language) }
    }
}
