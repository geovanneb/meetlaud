package com.meetlaud.domain

import java.text.Normalizer

/**
 * Foundation's string options on the JVM: compare without case and accents, and find text in the original by the
 * folded match. Each original character folds on its own, so a match maps back to exact original offsets.
 */
internal class FoldedText(val original: String) {
    val folded: String
    /** For each character of `folded`, the index in `original` it came from. One past the end is `original.length`. */
    private val origin: IntArray

    init {
        val builder = StringBuilder()
        val map = ArrayList<Int>()
        var index = 0
        while (index < original.length) {
            val codePoint = original.codePointAt(index)
            val count = Character.charCount(codePoint)
            val piece = fold(original.substring(index, index + count))
            for (char in piece) {
                builder.append(char)
                map.add(index)
            }
            index += count
        }
        map.add(original.length)
        folded = builder.toString()
        origin = map.toIntArray()
    }

    fun originalIndex(foldedIndex: Int): Int = origin[foldedIndex]

    /** The range in `original` of the first match of `needle` at or after `from` (an original index). */
    fun find(needle: String, from: Int): IntRange? {
        val target = fold(needle)
        if (target.isEmpty()) return null
        val start = origin.indexOfFirst { it >= from }.takeIf { it >= 0 } ?: return null
        val at = folded.indexOf(target, start)
        if (at < 0) return null
        return originalIndex(at) until originalIndex(at + target.length)
    }

    companion object {
        private val marks = Regex("\\p{Mn}+")

        /** Case-insensitive and diacritic-insensitive, as `.caseInsensitive` with `.diacriticInsensitive`. */
        fun fold(text: String): String =
            marks.replace(Normalizer.normalize(text, Normalizer.Form.NFD), "").lowercase()
    }
}

/** `localizedCaseInsensitiveContains` and its diacritic-insensitive cousin, for search. */
fun String.foldedContains(other: String): Boolean = FoldedText.fold(this).contains(FoldedText.fold(other))

/** Whether a code point is a letter, as Character.isLetter in Swift. */
internal fun isLetter(codePoint: Int): Boolean = Character.isLetter(codePoint)

/** Whether a code point is a number, as Character.isNumber in Swift: digits, and other numeric characters. */
internal fun isNumber(codePoint: Int): Boolean = when (Character.getType(codePoint).toByte()) {
    Character.DECIMAL_DIGIT_NUMBER, Character.LETTER_NUMBER, Character.OTHER_NUMBER -> true
    else -> false
}

/** Code points of a string, the closest Kotlin has to Swift's array of characters for these rules. */
internal fun String.codePointList(): List<Int> = codePoints().toArray().toList()

internal fun List<Int>.asString(): String = buildString { this@asString.forEach { appendCodePoint(it) } }

/** Trims whitespace and newlines, as `trimmingCharacters(in: .whitespacesAndNewlines)`. */
fun String.trimmedWhitespace(): String = trim { it.isWhitespace() || Character.isSpaceChar(it) }
