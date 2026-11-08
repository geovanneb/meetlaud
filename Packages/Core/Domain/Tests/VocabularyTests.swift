@testable import Domain
import Foundation
import Testing

struct VocabularyTests {
    private let entries = [
        VocabularyEntry(heard: "ana", written: "Anna"),
        VocabularyEntry(heard: "meet laud", written: "Meetlaud"),
    ]

    @Test func `a word is corrected wherever it appears, in any case`() {
        #expect(VocabularyCorrector.apply(entries, to: "ANA said ana was here") == "Anna said Anna was here")
    }

    @Test func `part of another word is left alone`() {
        #expect(VocabularyCorrector.apply(entries, to: "a banana for Mariana") == "a banana for Mariana")
    }

    @Test func `a phrase can be corrected too`() {
        #expect(VocabularyCorrector.apply(entries, to: "we use meet laud daily") == "we use Meetlaud daily")
    }

    @Test func `text with no spaces, such as Japanese, matches inside a sentence`() {
        let japanese = [VocabularyEntry(heard: "ミートロード", written: "Meetlaud")]
        #expect(VocabularyCorrector.apply(japanese, to: "これはミートロードです") == "これはMeetlaudです")
    }

    @Test func `an empty entry changes nothing`() {
        #expect(VocabularyCorrector.apply([VocabularyEntry(heard: " ", written: "x")], to: "a b") == "a b")
    }

    @Test func `the list survives being saved`() throws {
        let defaults = try #require(UserDefaults(suiteName: "vocabulary.test"))
        defaults.removePersistentDomain(forName: "vocabulary.test")
        VocabularyPreferences.save(entries, to: defaults)
        #expect(VocabularyPreferences.load(from: defaults) == entries)
    }

    @Test func `polish removes hesitations and keeps the words`() {
        #expect(TranscriptPolish.polish("Um, so uh we should ship") == "So we should ship")
        #expect(TranscriptPolish.polish("えーと、始めましょう") == "始めましょう")
    }

    @Test func `a phrase that is only hesitation stays, so a turn never disappears`() {
        #expect(TranscriptPolish.polish("Um...") == "Um...")
    }
}

struct FolderVocabularyTests {
    private let sales = FolderID()
    private let legal = FolderID()

    private var entries: [VocabularyEntry] {
        [
            VocabularyEntry(heard: "ana", written: "Anna"),
            VocabularyEntry(heard: "acme", written: "ACME"),
            VocabularyEntry(heard: "Ana", written: "Ana Paula", folderID: sales),
            VocabularyEntry(heard: "nda", written: "NDA", folderID: legal),
        ]
    }

    @Test func `a recording outside folders uses only the words for every recording`() {
        #expect(entries.applying(to: nil).map(\.written) == ["Anna", "ACME"])
    }

    @Test func `a folder adds its own words and leaves other folders out`() {
        #expect(entries.applying(to: legal).map(\.written) == ["NDA", "Anna", "ACME"])
    }

    @Test func `a folder spelling replaces the global one instead of being corrected twice`() {
        let words = entries.applying(to: sales)
        #expect(VocabularyCorrector.apply(words, to: "ana from acme") == "Ana Paula from ACME")
    }

    @Test func `a list saved before folders existed still loads`() throws {
        let old = Data(#"[{"id":"9A4C1F2E-0000-4000-8000-000000000000","heard":"ana","written":"Anna"}]"#.utf8)
        let decoded = try JSONDecoder().decode([VocabularyEntry].self, from: old)
        #expect(decoded.first?.folderID == nil)
        #expect(decoded.first?.written == "Anna")
    }
}
