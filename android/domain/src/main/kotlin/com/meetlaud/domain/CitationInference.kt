package com.meetlaud.domain


/** Gives each sentence of an answer written without citations the one line it clearly rests on. */
internal object CitationInference {
    /** At least this many of the sentence's words have to be in the line, and this share of them. */
    const val MINIMUM_SHARED = 2
    const val MINIMUM_SHARE = 0.4

    fun cite(body: String, excerpts: List<AskExcerpt>): AnswerParser.Result {
        val lines = excerpts.map { words(it.text) }
        val kept = mutableListOf<String>()
        val numbering = HashMap<Int, Int>()
        val citations = mutableListOf<Citation>()
        for (sentence in sentences(body)) {
            val index = bestLine(sentence, lines) ?: continue
            val shown = numbering[index] ?: (citations.size + 1).also { shown ->
                numbering[index] = shown
                val excerpt = excerpts[index]
                citations.add(Citation(shown, excerpt.recordingID, excerpt.title, excerpt.time, excerpt.text))
            }
            kept.add(marked(sentence, shown))
        }
        if (citations.isEmpty()) return AnswerParser.Result("", emptyList(), false)
        return AnswerParser.Result(kept.joinToString(" "), citations, true)
    }

    /** The line sharing the most words with the sentence, the earliest when tied. Null when none is close enough. */
    fun bestLine(sentence: String, lines: List<Set<String>>): Int? {
        val terms = words(sentence)
        if (terms.size < MINIMUM_SHARED) return null
        var best: Pair<Int, Int>? = null
        lines.forEachIndexed { index, line ->
            val shared = terms.intersect(line).size
            if (shared > (best?.second ?: 0)) best = index to shared
        }
        val found = best ?: return null
        if (found.second < MINIMUM_SHARED || found.second.toDouble() / terms.size < MINIMUM_SHARE) return null
        return found.first
    }

    /** Sentences, with list lines counted as sentences too. */
    fun sentences(text: String): List<String> {
        val result = mutableListOf<String>()
        for (sentence in TextBreaks.split(text, TextBreaks.Unit.SENTENCE)) {
            for (line in sentence.split('\n', '\r', '\u000B', '\u000C', '\u0085', '\u2028', '\u2029')) {
                val trimmed = line.trim { it == ' ' || it == '\t' }
                if (trimmed.isNotEmpty()) result.add(trimmed)
            }
        }
        return result
    }

    /** The marker goes before the closing punctuation, where the model would have put it. */
    fun marked(sentence: String, number: Int): String {
        val end = sentence.reversed().takeWhile { it in ".!?。！？" }.length
        val words = sentence.dropLast(end).trim { it == ' ' || it == '\t' }
        return "$words [$number]${sentence.takeLast(end)}"
    }

    /** The words that carry meaning. Words like "the" or "que" are in every line, so they prove nothing. */
    fun words(text: String): Set<String> = QueryTerms.terms(text, Int.MAX_VALUE).filter { it !in stopWords }.toSet()

    val stopWords = setOf(
        // English
        "the", "and", "was", "were", "are", "for", "that", "this", "with", "from", "they", "their", "there", "have",
        "has", "had", "but", "not", "you", "what", "which", "who", "about", "also", "will", "would", "been", "into",
        "its", "our", "them", "then", "than", "very", "main", "topic", "meeting", "discussed", "talked", "said",
        // Portuguese
        "que", "não", "uma", "para", "com", "por", "dos", "das", "foi", "são", "sobre", "como", "mais", "isso",
        "essa", "esse", "reunião", "principal", "tema", "assunto",
        // Spanish, without the ones Portuguese already has
        "los", "las", "del", "fue", "más", "eso", "esta", "este", "reunión",
        // Japanese
        "です", "ます", "した", "して", "この", "その", "あの", "こと", "もの", "ため", "会議", "について",
    )
}
