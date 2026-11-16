import Foundation

/// A rough token count. Models count Japanese close to one token per character, and Latin text near four per token.
public enum TokenEstimator {
    public static func tokens(in text: String) -> Int {
        var latin = 0
        var wide = 0
        for scalar in text.unicodeScalars {
            if scalar.value > 0x2E7F {
                wide += 1
            } else {
                latin += 1
            }
        }
        return wide + latin / 4 + 1
    }
}

/// Turns a transcript into the lines a model reads, and into pieces that fit its context.
public enum TranscriptFormatter {
    public static func displayName(of speaker: Speaker?) -> String? {
        speaker.map { $0.name ?? "Speaker \($0.number)" }
    }

    /// `[75] Ana: Let us start.` The number is how a claim finds its way back to the audio.
    public static func lines(segments: [TranscriptSegment], speakers: [Speaker]) -> [String] {
        segments.map { segment in
            let speaker = speakers.first { $0.id.uuidString == segment.speaker }
            let prefix = displayName(of: speaker).map { "\($0): " } ?? ""
            return "[\(Int(segment.start))] \(prefix)\(segment.text)"
        }
    }

    public static func chunks(_ lines: [String], limit: Int) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        var size = 0
        for line in lines {
            let tokens = TokenEstimator.tokens(in: line)
            if size + tokens > limit, !current.isEmpty {
                result.append(current)
                current = []
                size = 0
            }
            current.append(line)
            size += tokens
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}

/// Reads what the model wrote. Models drift from any format, so this accepts what it reasonably can and never throws.
public enum SummaryParser {
    public static func items(from text: String, kind: SectionKind) -> [SummaryItem] {
        let items = text.split(whereSeparator: \.isNewline).compactMap { item(from: String($0), kind: kind) }
        // Models overrun a limit in a prompt and repeat themselves, and they list the most important first when asked.
        return Array(unique(items).prefix(SummaryLimits.limit(for: kind)))
    }

    /// Keeps the first of items that say the same thing.
    static func unique(_ items: [SummaryItem]) -> [SummaryItem] {
        var seen: Set<String> = []
        return items.filter { seen.insert(normalized($0.text)).inserted }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Combines the items from each part of a long meeting, taking one from each in turn. A model reading a whole
    /// meeting at once favors how it ended, and a summary has to cover the start too.
    public static func balanced(_ parts: [[SummaryItem]], kind: SectionKind) -> [SummaryItem] {
        var taken: [SummaryItem] = []
        var depth = 0
        while parts.contains(where: { $0.count > depth }) {
            taken += parts.compactMap { $0.count > depth ? $0[depth] : nil }
            depth += 1
        }
        let kept = unique(taken).prefix(SummaryLimits.limit(for: kind))
        // Chosen by turn, and read in the order things happened.
        return kept.sorted { ($0.sourceTime ?? .infinity) < ($1.sourceTime ?? .infinity) }
    }

    /// An item written back in the format the model reads, to hand it to the model again.
    public static func line(for item: SummaryItem, kind: SectionKind) -> String {
        let time = item.sourceTime.map { "[\(Int($0))] " } ?? ""
        guard kind == .tasks else { return time + item.text }
        return "\(time)\(item.owner ?? "-") | \(item.text) | \(item.due ?? "-")"
    }

    /// Notes keep their `[seconds]`, and lose everything around it.
    public static func notes(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let cleaned = cleanBullet(String(line))
            let (time, rest) = splitTime(cleaned)
            guard !rest.isEmpty else { return nil }
            return time.map { "[\(Int($0))] \(rest)" } ?? rest
        }
    }

    private static func item(from line: String, kind: SectionKind) -> SummaryItem? {
        let cleaned = cleanBullet(line)
        guard !isHeading(cleaned) else { return nil }
        let (time, written) = splitTime(cleaned)
        let rest = withoutEchoedFormat(written)
        // A model stuck in a loop writes the same words over and over, and nothing in such a line can be trusted.
        guard !rest.isEmpty, !isPlaceholder(rest), TranscriptCleanup.markRepeats(rest) == rest else { return nil }

        guard kind == .tasks else { return SummaryItem(text: rest, sourceTime: time) }

        var parts = rest.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        // A model sometimes echoes the format, and writes the real owner in the next column.
        if parts.count > 3, isPlaceholder(parts[0]) {
            parts.removeFirst()
        }
        guard parts.count >= 2 else { return SummaryItem(text: rest, sourceTime: time) }
        return SummaryItem(
            text: parts[1],
            sourceTime: time,
            owner: unknownToNil(parts[0]),
            due: parts.count > 2 ? unknownToNil(parts[2]) : nil,
        )
    }

    private static func unknownToNil(_ text: String) -> String? {
        let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: " -–—"))
        return cleaned.isEmpty || isPlaceholder(cleaned) ? nil : cleaned
    }

    /// The names of the columns in the prompt, which are not an answer.
    private static func isPlaceholder(_ text: String) -> Bool {
        ["owner", "task", "due date", "date", "unknown", "none", "n/a", "item", "note"].contains(text.lowercased())
    }

    /// The prompt says "[seconds] item", and a small model sometimes starts each line with "Item:".
    private static func withoutEchoedFormat(_ text: String) -> String {
        for word in ["Item:", "item:", "Note:", "note:"] where text.hasPrefix(word) {
            return text.dropFirst(word.count).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    private static func cleanBullet(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        while let first = text.first, "-*•・".contains(first) {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return text.replacing("**", with: "")
    }

    private static func isHeading(_ line: String) -> Bool {
        line.hasPrefix("#") || line.hasPrefix("|") || (line.hasSuffix(":") && line.count < 40)
    }

    /// Accepts `[75]`, `[75.2]`, and `[1:15]`.
    private static func splitTime(_ line: String) -> (TimeInterval?, String) {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return (nil, line) }
        let inside = line[line.index(after: line.startIndex) ..< close]
        let rest = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
        let parts = inside.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty, parts.count == inside.split(separator: ":").count else { return (nil, line) }
        return (parts.reduce(0) { $0 * 60 + $1 }, rest)
    }
}

/// Ties a model's claims back to the transcript, because models state wrong things with total confidence.
public enum SummaryValidator {
    /// Numbers can always be checked. Words only when the summary is in the meeting's language: a translated
    /// "Friday" would not be found in the transcript, and it may well have been said.
    static func isSaid(_ due: String, in segments: [TranscriptSegment], sameLanguage: Bool) -> Bool {
        let numbers = due.split { !$0.isNumber }.map(String.init)
        if !numbers.isEmpty {
            return numbers.allSatisfy { number in segments.contains { $0.text.contains(number) } }
        }
        guard sameLanguage else { return true }
        let words = due.split { !$0.isLetter }.map(String.init)
        return words.contains { word in segments.contains { $0.text.localizedCaseInsensitiveContains(word) } }
    }

    /// The example from the prompt, copied as if someone had said it. A meeting that really was about it keeps it.
    public static func isEchoedExample(_ item: SummaryItem, segments: [TranscriptSegment]) -> Bool {
        SummaryPrompts.exampleTasks.contains(item.text)
            && !segments.contains { $0.text.localizedCaseInsensitiveContains(item.text) }
    }

    /// How far a citation can sit from a real phrase.
    static let tolerance: TimeInterval = 10

    public static func validate(
        _ item: SummaryItem,
        segments: [TranscriptSegment],
        speakers: [Speaker],
        sameLanguage: Bool = true,
    ) -> SummaryItem {
        var item = item
        let source = item.sourceTime.flatMap { closest(to: $0, in: segments) }
        // A citation that points at nothing is worse than none: the link would look like proof.
        item.sourceTime = source?.start
        // Models fill an empty date with a plausible one, and a wrong deadline is worse than none.
        if let due = item.due, !isSaid(due, in: segments, sameLanguage: sameLanguage) {
            item.due = nil
        }
        item.needsReview = source == nil

        if let owner = item.owner {
            let known = speakers.compactMap(TranscriptFormatter.displayName(of:))
            let transcriptNames = segments.contains { $0.text.localizedCaseInsensitiveContains(owner) }
            if !known.contains(where: { $0.localizedCaseInsensitiveCompare(owner) == .orderedSame }), !transcriptNames {
                item.needsReview = true
            }
        }
        return item
    }

    private static func closest(to time: TimeInterval, in segments: [TranscriptSegment]) -> TranscriptSegment? {
        segments
            .filter { abs($0.start - time) <= tolerance || ($0.start <= time && time <= $0.end) }
            .min { abs($0.start - time) < abs($1.start - time) }
    }
}

/// Stores speakers as tokens, so that renaming someone later reaches summaries that are already written.
///
/// A token also keeps the name it replaced. Merging speakers or transcribing again removes the speaker it points at,
/// and readers must then see that name, not the token.
public enum SpeakerTokens {
    private static let tokenPattern = #"\{\{speaker:([0-9A-Fa-f-]+)\|([^}]*)\}\}"#

    public static func encode(_ text: String, speakers: [Speaker]) -> String {
        let named = speakers.compactMap { speaker in
            TranscriptFormatter.displayName(of: speaker).map { (name: $0, speaker: speaker) }
        }
        .sorted { $0.name.count > $1.name.count }
        guard !named.isEmpty else { return text }
        // One pass, longest first: "Ana Lima" must not become a token for "Ana", or "Speaker 10" for "Speaker 1".
        // The edges only look at Latin letters and digits, because Japanese has no spaces between words.
        let names = named.map { NSRegularExpression.escapedPattern(for: $0.name) }.joined(separator: "|")
        let pattern = #"(?<![\p{Latin}\p{Nd}])(?:"# + names + #")(?![\p{Latin}\p{Nd}])"#
        return replacing(pattern, in: text) { groups in
            guard let match = named.first(where: { $0.name == groups[0] }) else { return groups[0] }
            return "{{speaker:\(match.speaker.id.uuidString)|\(match.name)}}"
        }
    }

    public static func decode(
        _ text: String,
        speakers: [Speaker],
        name: (Speaker) -> String? = TranscriptFormatter.displayName(of:),
    ) -> String {
        replacing(tokenPattern, in: text) { groups in
            speakers.first { $0.id.uuidString.caseInsensitiveCompare(groups[1]) == .orderedSame }
                .flatMap(name) ?? groups[2]
        }
    }

    private static func replacing(_ pattern: String, in text: String, with replace: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let whole = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: whole).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let groups = (0 ..< match.numberOfRanges).map { index in
                Range(match.range(at: index), in: result).map { String(result[$0]) } ?? ""
            }
            result.replaceSubrange(range, with: replace(groups))
        }
        return result
    }
}

public enum TemplateError: Error, Equatable {
    case invalid
}

/// The rules for a template, and its file format. Files come from other people, so nothing in them is trusted.
public enum TemplateCodec {
    public enum Limits {
        public static let name = 80
        public static let instructions = 2000
        public static let sections = 12
    }

    private struct File: Codable {
        var schemaVersion: Int
        var name: String
        var category: TemplateCategory
        var instructions: String
        var sections: [TemplateSection]
    }

    private static let schemaVersion = 1

    public static func isValid(_ template: SummaryTemplate) -> Bool {
        let name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= Limits.name
            && template.instructions.count <= Limits.instructions
            && (1 ... Limits.sections).contains(template.sections.count)
            && template.sections.allSatisfy { section in
                let title = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return !title.isEmpty && title.count <= Limits.name
            }
    }

    public static func encode(_ template: SummaryTemplate) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(File(
            schemaVersion: schemaVersion, name: template.name, category: template.category,
            instructions: template.instructions, sections: template.sections,
        ))
    }

    /// Always a new user template: a file can neither replace an existing one nor pass for a built-in.
    public static func decode(_ data: Data) throws -> SummaryTemplate {
        guard let file = try? JSONDecoder().decode(File.self, from: data), file.schemaVersion == schemaVersion else {
            throw TemplateError.invalid
        }
        let template = SummaryTemplate(
            name: file.name, category: file.category, instructions: file.instructions, sections: file.sections,
        )
        guard isValid(template) else { throw TemplateError.invalid }
        return template
    }

    /// Reads what a model wrote when asked to design a template.
    public static func parseDraft(_ text: String) throws -> SummaryTemplate {
        var name = ""
        var instructions = ""
        var sections: [TemplateSection] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.replacing("**", with: "").split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " -*#")).lowercased() {
            case "name": name = String(value.prefix(Limits.name))
            case "instructions": instructions = String(value.prefix(Limits.instructions))
            case "section": sections.append(TemplateSection(title: String(value.prefix(Limits.name))))
            case "task section": sections.append(TemplateSection(
                    title: String(value.prefix(Limits.name)),
                    kind: .tasks,
                ))
            default: continue
            }
        }
        let template = SummaryTemplate(
            name: name, category: .general, instructions: instructions,
            sections: Array(sections.prefix(Limits.sections)),
        )
        guard isValid(template) else { throw TemplateError.invalid }
        return template
    }
}

public enum SummaryPreferences {
    public static let autoKey = "summary.auto"
    public static let profileKey = "ai.profile"
    public static let defaultTemplateKey = "summary.defaultTemplate"
    public static let profileLimit = 1500
}
