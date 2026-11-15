import Foundation

/// A word the engine gets wrong, and how it should be written. Names of people, products, and companies, mostly.
public struct VocabularyEntry: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var heard: String
    public var written: String
    /// Nil applies to every recording. A folder applies only to the recordings in it.
    public var folderID: FolderID?

    public init(id: UUID = UUID(), heard: String, written: String, folderID: FolderID? = nil) {
        self.id = id
        self.heard = heard
        self.written = written
        self.folderID = folderID
    }

    public var isValid: Bool {
        !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum VocabularyPreferences {
    public static let key = "transcript.vocabulary"

    public static func load(from defaults: UserDefaults = .standard) -> [VocabularyEntry] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([VocabularyEntry].self, from: $0) } ?? []
    }

    public static func save(_ entries: [VocabularyEntry], to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(entries), forKey: key)
    }
}

public extension [VocabularyEntry] {
    /// The entries for a recording in this folder. When a folder spells a word its own way, that spelling replaces the
    /// global one instead of running after it, so that "ana" never becomes "Ana Paula" and then "Anna Paula".
    func applying(to folder: FolderID?) -> [VocabularyEntry] {
        let local = filter { folder != nil && $0.folderID == folder }
        let overridden = Set(local.map(\.key))
        return local + filter { $0.folderID == nil && !overridden.contains($0.key) }
    }
}

private extension VocabularyEntry {
    var key: String {
        heard.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil,
        )
    }
}

/// Corrects text after transcription, which works with every engine.
public enum VocabularyCorrector {
    public static func apply(_ entries: [VocabularyEntry], to text: String) -> String {
        entries.filter(\.isValid).reduce(text) { result, entry in
            replace(entry.heard, with: entry.written, in: result)
        }
    }

    /// Whole words only, so that "ana" never changes "banana". Text with no spaces between words, such as Japanese,
    /// has no boundaries to look for, so it matches anywhere.
    private static func replace(_ heard: String, with written: String, in text: String) -> String {
        let needle = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesWords = needle.unicodeScalars.allSatisfy { !isCJK($0) }
        var result = ""
        var rest = text[...]
        while let range = rest.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) {
            let startsWord = range.lowerBound == text.startIndex || !text[text.index(before: range.lowerBound)].isLetter
            let endsWord = range.upperBound == text.endIndex || !text[range.upperBound].isLetter
            result += rest[..<range.lowerBound]
            result += !usesWords || (startsWord && endsWord) ? written : String(rest[range])
            rest = rest[range.upperBound...]
        }
        return result + rest
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x3040 ... 0x30FF).contains(scalar.value) || (0x4E00 ... 0x9FFF).contains(scalar.value)
    }
}

/// Removes hesitations for reading. It works on what is shown and never on what is stored, so the original is always
/// one tap away and evidence links keep pointing at the real words.
public enum TranscriptPolish {
    private static let spaced = ["um", "umm", "uh", "uhh", "erm", "hmm", "ãh", "éé", "hum", "eh", "ehh"]
    private static let unspaced = ["えーと", "えっと", "あのー", "えー"]

    public static func polish(_ text: String) -> String {
        var result = text
        for filler in unspaced {
            result = result.replacing(filler, with: "")
        }
        let words = result.split(separator: " ", omittingEmptySubsequences: true).filter { word in
            !spaced.contains(word.lowercased().trimmingCharacters(in: .punctuationCharacters))
        }
        // Punctuation left behind by a hesitation at the start reads as a mistake.
        let cleaned = words.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines
                .union(.punctuationCharacters.subtracting(.init(charactersIn: "\"'"))))
        // A phrase that was only hesitation stays as it was: an empty line would hide that someone spoke.
        guard let first = cleaned.first else { return text }
        return first.uppercased() + cleaned.dropFirst()
    }
}
