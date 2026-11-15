package com.meetlaud.app.domain

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.meetlaud.domain.AnswerParser
import com.meetlaud.domain.AskExcerpt
import com.meetlaud.domain.AskPrompts
import com.meetlaud.domain.RecordingID
import com.meetlaud.domain.SpeakerTokens
import com.meetlaud.domain.SummaryParser
import com.meetlaud.domain.SectionKind
import com.meetlaud.domain.localizedStandardCompare
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

/**
 * The domain's text handling, run by Android's own regular expression engine. Unit tests run on the JVM, whose engine
 * accepts patterns Android rejects: (?U) passed every unit test and crashed the app on its first question.
 */
@RunWith(AndroidJUnit4::class)
class DomainTextOnDevice {
    private val recording = RecordingID(UUID.randomUUID())
    private val excerpts = listOf(
        AskExcerpt(recording, "Planning call", 12.0, text = "We have about 20 percent more budget than last year."),
        AskExcerpt(recording, "Planning call", 31.0, text = "Most of it goes into the video production."),
    )

    @Test fun anAnswerIsBuiltAndParsed() {
        val request = AskPrompts.answer("How much budget is there?", excerpts, emptyList(), emptyList(), null)
        assertTrue(request.prompt.contains("[1]"))
        val result = AnswerParser.parse("The budget grew by about 20 percent [1], mostly for video [ 2 ].", excerpts)
        assertEquals(2, result.citations.size)
        assertTrue(result.hasBasis)
        // A full-width digit, as Japanese answers sometimes write it, still cites.
        assertEquals(1, AnswerParser.parse("予算は増えました [１]。", excerpts).citations.size)
    }

    @Test fun aRefusalIsRecognized() {
        val result = AnswerParser.parse(" NOT_FOUND.", excerpts)
        assertEquals("", result.body)
    }

    @Test fun summariesAndNamesParse() {
        val items = SummaryParser.items("[12] The budget grew.\n[31] Video comes first.", SectionKind.BULLETS)
        assertEquals(listOf(12.0, 31.0), items.map { it.sourceTime })
        assertEquals("Ana", SpeakerTokens.decode("{{speaker:${UUID.randomUUID()}|Ana}}", emptyList()))
        assertTrue(localizedStandardCompare("Meeting 2", "Meeting 10") < 0)
    }
}
