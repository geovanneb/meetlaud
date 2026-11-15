package com.meetlaud.domain

import java.text.BreakIterator
import java.util.Locale

/**
 * Where words and sentences begin, as Foundation's `enumerateSubstrings` finds them. Both platforms use ICU for this:
 * on Android, `java.text.BreakIterator` is ICU with its dictionaries, so Japanese splits into real words the way it
 * does on iOS. A desktop JVM has no Japanese dictionary, so the unit tests install ICU4J here, to test what the phone
 * does.
 */
object TextBreaks {
    enum class Unit { WORD, SENTENCE }

    /** Returns every piece between two breaks, spaces and punctuation included. */
    @Volatile
    var breaker: (text: String, unit: Unit, locale: Locale) -> List<String> = ::platform

    fun split(text: String, unit: Unit, locale: Locale = Locale.getDefault()): List<String> = breaker(text, unit, locale)

    private fun platform(text: String, unit: Unit, locale: Locale): List<String> {
        val iterator = if (unit == Unit.WORD) BreakIterator.getWordInstance(locale) else BreakIterator.getSentenceInstance(locale)
        iterator.setText(text)
        val result = mutableListOf<String>()
        var start = iterator.first()
        var end = iterator.next()
        while (end != BreakIterator.DONE) {
            result.add(text.substring(start, end))
            start = end
            end = iterator.next()
        }
        return result
    }
}
