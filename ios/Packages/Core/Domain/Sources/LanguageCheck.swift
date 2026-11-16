import Foundation

/// A rough check that a line of a summary is in the language it should be. Small models drift back to the language of
/// the transcript, so a summary asked for in Japanese can come back in Portuguese.
///
/// It says a line is wrong only when it is fairly sure. Japanese is told apart by its script. English, Portuguese, and
/// Spanish share a script, so they are told apart by short words that only one of them uses.
public enum LanguageCheck {
    private static let words: [String: Set<String>] = [
        "en": [
            "the", "and", "to", "of", "is", "are", "will", "for", "with", "that", "this", "by", "on", "it", "be",
            "we", "they", "should", "not", "was", "has", "have", "from", "about", "who", "what", "if", "or", "i", "yes",
        ],
        "pt": [
            "não", "é", "uma", "um", "com", "os", "da", "dos", "das", "em", "na", "nas", "vai", "vão", "ele", "ela",
            "isso", "mas", "até", "pelo", "pela", "ao", "também", "são", "foi", "e", "ou", "quem", "precisa", "você",
            "eles", "eu", "sim", "nós", "nisso", "agora", "ainda",
        ],
        "es": [
            "es", "una", "un", "con", "los", "las", "del", "el", "la", "en", "por", "lo", "va", "hasta", "pero", "más",
            "y", "fue", "también", "son", "si", "quién", "necesita", "ellos", "usted", "yo", "sí", "nosotros", "ahora",
            "todavía",
        ],
    ]

    /// True only when the text is clearly in another language than `language`.
    public static func isWrong(_ text: String, for language: String) -> Bool {
        var kana = 0
        var han = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040 ... 0x30FF: kana += 1
            case 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF: han += 1
            case 0x41 ... 0x5A, 0x61 ... 0x7A, 0xC0 ... 0x24F: latin += 1
            default: continue
            }
        }
        if language == "ja" {
            // Names and terms can stay in Latin letters, so a little of them is fine.
            return latin > 0 && (kana + han) * 3 < latin
        }
        // A name kept in kanji is fine inside a sentence, but a line mostly in Japanese script is not.
        if kana + han >= 2, (kana + han) * 2 > latin {
            return true
        }
        guard let own = words[language] else { return false }
        let tokens = text.lowercased().split { !$0.isLetter }.map(String.init)
        let ownCount = tokens.count { own.contains($0) }
        let otherCount = words.filter { $0.key != language }.values.map { set in tokens.count { set.contains($0) } }
            .max() ?? 0
        return otherCount >= 2 && otherCount > ownCount * 2
    }
}
