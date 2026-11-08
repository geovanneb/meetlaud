import Foundation

public enum TranscriptFormat: String, CaseIterable, Sendable {
    case txt, markdown = "md", srt, vtt

    public var usesOptions: Bool {
        self == .txt || self == .markdown
    }
}

public struct ExportOptions: Hashable, Sendable {
    public var includesSpeakers: Bool
    public var includesTimestamps: Bool

    public init(includesSpeakers: Bool = true, includesTimestamps: Bool = true) {
        self.includesSpeakers = includesSpeakers
        self.includesTimestamps = includesTimestamps
    }
}

/// Turns a transcript into a file. Subtitle formats always carry times, because they are made of them.
public enum TranscriptExporter {
    public static func text(
        title: String,
        segments: [TranscriptSegment],
        speakers: [Speaker],
        format: TranscriptFormat,
        options: ExportOptions = ExportOptions(),
    ) -> String {
        switch format {
        case .txt:
            lines(segments, speakers, options).joined(separator: "\n") + "\n"
        case .markdown:
            "# \(title)\n\n" + lines(segments, speakers, options, bold: true).joined(separator: "\n\n") + "\n"
        case .srt:
            segments.enumerated().map { index, segment in
                let time = "\(stamp(segment.start, ",")) --> \(stamp(segment.end, ","))"
                return "\(index + 1)\n\(time)\n\(cue(segment, speakers, options))\n"
            }
            .joined(separator: "\n")
        case .vtt:
            "WEBVTT\n\n" + segments.map { segment in
                let time = "\(stamp(segment.start, ".")) --> \(stamp(segment.end, "."))"
                return "\(time)\n\(cue(segment, speakers, options))\n"
            }
            .joined(separator: "\n")
        }
    }

    private static func name(_ segment: TranscriptSegment, _ speakers: [Speaker]) -> String? {
        TranscriptFormatter.displayName(of: speakers.first { $0.id.uuidString == segment.speaker })
    }

    private static func cue(_ segment: TranscriptSegment, _ speakers: [Speaker], _ options: ExportOptions) -> String {
        // A line break inside a cue is legal, and a blank line would end it early.
        let text = segment.text.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard options.includesSpeakers, let name = name(segment, speakers) else { return text }
        return "\(name): \(text)"
    }

    private static func lines(
        _ segments: [TranscriptSegment],
        _ speakers: [Speaker],
        _ options: ExportOptions,
        bold: Bool = false,
    ) -> [String] {
        segments.map { segment in
            var prefix = options.includesTimestamps ? "[\(clock(segment.start))] " : ""
            if options.includesSpeakers, let name = name(segment, speakers) {
                prefix += bold ? "**\(name):** " : "\(name): "
            }
            return prefix + segment.text
        }
    }

    public static func clock(_ time: TimeInterval) -> String {
        let total = Int(max(0, time))
        let (hours, minutes, seconds) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    private static func stamp(_ time: TimeInterval, _ separator: String) -> String {
        let milliseconds = Int((max(0, time) * 1000).rounded())
        let (hours, minutes) = (milliseconds / 3_600_000, milliseconds / 60000 % 60)
        let (seconds, rest) = (milliseconds / 1000 % 60, milliseconds % 1000)
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, seconds, separator, rest)
    }
}

public enum SummaryExporter {
    public static func markdown(title: String, summary: Summary, speakers: [Speaker]) -> String {
        var result = "# \(title)\n\n"
        for section in summary.sections {
            result += "## \(section.title)\n\n"
            for item in section.items {
                result += line(item, kind: section.kind, speakers: speakers) + "\n"
            }
            result += "\n"
        }
        return result
    }

    private static func line(_ item: SummaryItem, kind: SectionKind, speakers: [Speaker]) -> String {
        var text = SpeakerTokens.decode(item.text, speakers: speakers)
        if let owner = item.owner {
            text = "\(SpeakerTokens.decode(owner, speakers: speakers)): \(text)"
        }
        if let due = item.due {
            text += " (\(due))"
        }
        if let time = item.sourceTime {
            text += " [\(TranscriptExporter.clock(time))]"
        }
        switch kind {
        case .bullets: return "- \(text)"
        case .tasks: return "- [\(item.isDone ? "x" : " ")] \(text)"
        }
    }
}

/// A title can hold anything, and a file name cannot.
public enum ExportFileName {
    public static func safe(_ title: String, fileExtension: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleaned = title.unicodeScalars.map { banned.contains($0) ? " " : String($0) }.joined()
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        let name = cleaned.isEmpty ? "Meeting" : String(cleaned.prefix(80))
        return "\(name).\(fileExtension)"
    }
}
