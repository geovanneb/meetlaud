package com.meetlaud.domain

/** Fixes two ways a speech model fails on noise, before the text is saved. */
object TranscriptCleanup {
    /** This many times in a row is a model stuck in a loop. People repeat themselves less, and numbers never count. */
    internal const val LOOP = 6
    internal const val LONGEST_PIECE = 40

    /**
     * On noise, a model can write the same words over and over. One copy stays, followed by "[×N]", so the reader
     * knows text was left out. Numbers are never touched, and a piece starts at a word, so words stay whole.
     */
    fun markRepeats(text: String): String {
        val characters = text.codePointList()
        val output = StringBuilder()
        var index = 0
        while (index < characters.size) {
            val run = repeatedRun(characters, index)
            if (run != null) {
                output.append(run.piece.asString()).append(" [×${run.count}]")
                index = run.end
            } else {
                output.appendCodePoint(characters[index])
                index += 1
            }
        }
        return output.toString()
    }

    /** Whether the text holds a word: a letter or a digit, in any script. */
    fun hasWords(text: String): Boolean {
        // Whisper can emit this annotation for silence; it is not something a participant said.
        if (text.trimmedWhitespace() == "[BLANK_AUDIO]") return false
        return text.codePoints().anyMatch { Character.isLetter(it) || Character.isDigit(it) }
    }

    private class Run(val piece: List<Int>, val count: Int, val end: Int)

    private fun repeatedRun(characters: List<Int>, start: Int): Run? {
        if (isBetween(characters[start])) return null
        // Inside a word in a script with spaces, a piece would cut the word.
        if (start > 0 && isSpacedLetter(characters[start - 1]) && isSpacedLetter(characters[start])) return null
        var size = 2
        while (size <= LONGEST_PIECE && start + size <= characters.size) {
            val piece = characters.subList(start, start + size)
            if (piece.any(::isLetter) && piece.none(::isNumber) && !isBetween(piece.last())) {
                val (count, end) = repeats(piece, characters, start)
                if (count >= LOOP) return Run(piece.toList(), count, end)
            }
            size += 1
        }
        return null
    }

    /** How many times `piece` stands at `start`, with spaces or commas between, and where that ends. */
    private fun repeats(piece: List<Int>, characters: List<Int>, start: Int): Pair<Int, Int> {
        var count = 0
        var position = start
        var end = start
        while (position + piece.size <= characters.size && characters.subList(position, position + piece.size) == piece) {
            val next = position + piece.size
            // A matching prefix is not a repeated word: five "no"s followed by "nobody" must stay intact.
            if (next < characters.size && isSpacedLetter(piece.last()) && isSpacedLetter(characters[next])) break
            count += 1
            position = next
            end = position
            while (position < characters.size && isBetween(characters[position])) position += 1
        }
        return count to (if (position == characters.size) position else end)
    }

    private val between = setOf(','.code, '.'.code, '、'.code, '，'.code, '。'.code)

    private fun isBetween(codePoint: Int): Boolean = Character.isWhitespace(codePoint) || Character.isSpaceChar(codePoint) || codePoint in between

    /** Latin, Cyrillic, and Greek letters: scripts that put spaces between words. */
    private fun isSpacedLetter(codePoint: Int): Boolean {
        if (!Character.isLetter(codePoint)) return false
        return codePoint in 0x0041..0x024F || codePoint in 0x0370..0x03FF || codePoint in 0x0400..0x04FF || codePoint in 0x1E00..0x1EFF
    }
}
