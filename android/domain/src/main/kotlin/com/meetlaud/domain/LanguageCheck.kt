package com.meetlaud.domain

/**
 * A rough check that a line of a summary is in the language it should be. Small models drift back to the language of
 * the transcript. It says a line is wrong only when it is fairly sure.
 */
object LanguageCheck {
    private val words: Map<String, Set<String>> = mapOf(
        "en" to setOf(
            "the", "and", "to", "of", "is", "are", "will", "for", "with", "that", "this", "by", "on", "it", "be",
            "we", "they", "should", "not", "was", "has", "have", "from", "about", "who", "what", "if", "or", "i", "yes",
        ),
        "pt" to setOf(
            "não", "é", "uma", "um", "com", "os", "da", "dos", "das", "em", "na", "nas", "vai", "vão", "ele", "ela",
            "isso", "mas", "até", "pelo", "pela", "ao", "também", "são", "foi", "e", "ou", "quem", "precisa", "você",
            "eles", "eu", "sim", "nós", "nisso", "agora", "ainda",
        ),
        "es" to setOf(
            "es", "una", "un", "con", "los", "las", "del", "el", "la", "en", "por", "lo", "va", "hasta", "pero", "más",
            "y", "fue", "también", "son", "si", "quién", "necesita", "ellos", "usted", "yo", "sí", "nosotros", "ahora",
            "todavía",
        ),
    )

    /** True only when the text is clearly in another language than `language`. */
    fun isWrong(text: String, language: String): Boolean {
        var kana = 0
        var han = 0
        var latin = 0
        text.codePoints().forEach { value ->
            when (value) {
                in 0x3040..0x30FF -> kana += 1
                in 0x3400..0x4DBF, in 0x4E00..0x9FFF -> han += 1
                in 0x41..0x5A, in 0x61..0x7A, in 0xC0..0x24F -> latin += 1
            }
        }
        if (language == "ja") {
            // Names and terms can stay in Latin letters, so a little of them is fine.
            return latin > 0 && (kana + han) * 3 < latin
        }
        // A name kept in kanji is fine inside a sentence, but a line mostly in Japanese script is not.
        if (kana + han >= 2 && (kana + han) * 2 > latin) return true
        val own = words[language] ?: return false
        val tokens = splitWords(text.lowercase())
        val ownCount = tokens.count { it in own }
        val otherCount = words.filter { it.key != language }.values.maxOfOrNull { set -> tokens.count { it in set } } ?: 0
        return otherCount >= 2 && otherCount > ownCount * 2
    }

    /** Runs of letters, as `split { !$0.isLetter }`. */
    internal fun splitWords(text: String): List<String> {
        val result = mutableListOf<String>()
        val current = StringBuilder()
        text.codePoints().forEach { codePoint ->
            if (Character.isLetter(codePoint)) {
                current.appendCodePoint(codePoint)
            } else if (current.isNotEmpty()) {
                result.add(current.toString())
                current.clear()
            }
        }
        if (current.isNotEmpty()) result.add(current.toString())
        return result
    }
}
