import Foundation

/// Fixes two ways a speech model fails on noise, before the text is saved. Ported from the rules that hold up in
/// Get Things Done's transcription.
public enum TranscriptCleanup {
    /// This many times in a row is a model stuck in a loop. People repeat themselves less, and numbers never count.
    static let loop = 6
    static let longestPiece = 40

    /// On noise, a model can write the same words over and over. One copy stays, followed by "[×N]", so the reader
    /// knows text was left out. The mark has no words, so it reads the same in every language. Numbers are never
    /// touched, and a piece starts at a word, so words themselves stay whole.
    public static func markRepeats(_ text: String) -> String {
        let characters = Array(text)
        var output = ""
        var index = 0
        while index < characters.count {
            if let run = repeatedRun(in: characters, at: index) {
                output += String(run.piece) + " [×\(run.count)]"
                index = run.end
            } else {
                output.append(characters[index])
                index += 1
            }
        }
        return output
    }

    /// Whether the text holds a word: a letter or a digit, in any script. A model that does not know the language
    /// can return only "," or "…", which is no speech at all.
    public static func hasWords(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
    }

    private struct Run {
        let piece: ArraySlice<Character>
        let count: Int
        let end: Int
    }

    private static func repeatedRun(in characters: [Character], at start: Int) -> Run? {
        guard !isBetween(characters[start]) else { return nil }
        // Inside a word in a script with spaces, a piece would cut the word.
        if start > 0, isSpacedLetter(characters[start - 1]), isSpacedLetter(characters[start]) {
            return nil
        }
        var size = 2
        while size <= longestPiece, start + size <= characters.count {
            let piece = characters[start ..< start + size]
            if piece.contains(where: \.isLetter), !piece.contains(where: \.isNumber), let last = piece.last,
               !isBetween(last)
            {
                let run = repeats(of: piece, in: characters, from: start)
                if run.count >= loop {
                    return Run(piece: piece, count: run.count, end: run.end)
                }
            }
            size += 1
        }
        return nil
    }

    /// How many times `piece` stands at `start`, with spaces or commas between, and where that ends.
    private static func repeats(
        of piece: ArraySlice<Character>,
        in characters: [Character],
        from start: Int,
    ) -> (count: Int, end: Int) {
        var count = 0
        var position = start
        var end = start
        while position + piece.count <= characters.count,
              characters[position ..< position + piece.count].elementsEqual(piece)
        {
            count += 1
            position += piece.count
            end = position
            while position < characters.count, isBetween(characters[position]) {
                position += 1
            }
        }
        return (count, position == characters.count ? position : end)
    }

    private static func isBetween(_ character: Character) -> Bool {
        character.isWhitespace || [",", ".", "、", "，", "。"].contains(character)
    }

    /// Latin, Cyrillic, and Greek letters: scripts that put spaces between words.
    private static func isSpacedLetter(_ character: Character) -> Bool {
        guard character.isLetter, let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x0041 ... 0x024F, 0x0370 ... 0x03FF, 0x0400 ... 0x04FF, 0x1E00 ... 0x1EFF: return true
        default: return false
        }
    }
}
