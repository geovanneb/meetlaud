package com.meetlaud.app.infra.engines

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.meetlaud.app.infra.audio.SpeechWindowReader
import com.meetlaud.app.infra.modeldelivery.BundledCatalog
import com.meetlaud.app.infra.modeldelivery.ModelDownloader
import com.meetlaud.domain.InstallState
import com.meetlaud.domain.LanguageRequest
import com.meetlaud.domain.ModelDescriptor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import kotlin.math.sqrt

/**
 * The engines on a real device or emulator, with the real models: downloaded through ModelDownloader, checked by
 * hash, then run. Slow and online, so they run on request only:
 *   make android-test-ui ARGS="-Pandroid.testInstrumentationRunnerArguments.class=com.meetlaud.app.infra.engines.EngineTests"
 * Models stay in the test app's files between runs, so only the first run downloads.
 */
@RunWith(AndroidJUnit4::class)
class EngineTests {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    init { com.meetlaud.app.infra.system.ForegroundWork.install(InstrumentationRegistry.getInstrumentation().targetContext) }
    private val root = File(context.filesDir, "EngineTests/models")
    private val catalog = BundledCatalog(context)
    private val downloader = ModelDownloader(context, root, catalog.models, { Long.MAX_VALUE }) {}

    private fun install(id: String): Pair<ModelDescriptor, File> = runBlocking {
        val model = catalog.models.first { it.id == id }
        if (downloader.folder(id) == null) {
            downloader.install(model, allowsCellular = true)
            withTimeout(60 * 60 * 1000L) {
                downloader.events.first { (event, state) -> event == id && (state == InstallState.Ready || state is InstallState.Failed || state is InstallState.Paused) }
            }
        }
        model to (downloader.folder(id) ?: error("$id did not install: ${downloader.state(id)}"))
    }

    private fun speedClip(): File = File(context.cacheDir, "speed-test.m4a").apply {
        if (!exists()) context.assets.open("speed-test.m4a").use { input -> outputStream().use { input.copyTo(it) } }
    }

    @Test fun whisperTranscribesTheSpeedClip() = runBlocking {
        val (model, folder) = install("whisper-small")
        val window = SpeechWindowReader().windows(speedClip(), 0.0).firstOrNull() ?: error("No audio")
        val engine = WhisperCppEngine()
        engine.prepare(model, folder)
        val started = System.nanoTime()
        val result = engine.transcribe(window, "en")
        val seconds = (System.nanoTime() - started) / 1e9
        engine.unload()
        val text = result.segments.joinToString(" ") { it.text }
        println("whisper-small: ${window.end - window.start} s of audio in $seconds s: $text")
        assertEquals("en", result.language)
        // The clip is a public domain reading of The Art of War, the part about the five constant factors.
        assertTrue(text, text.contains("moral law", ignoreCase = true))
        assertTrue(result.segments.all { it.start >= window.start && it.end <= window.end + 1 })
    }

    @Test fun qwenWritesAnAnswer() = runBlocking {
        val (model, folder) = install("qwen35-2b")
        val engine = LlamaLanguageEngine()
        engine.prepare(model, folder)
        val text = engine.generate(LanguageRequest("You answer in one short sentence.", "What color is a clear sky at noon?", 40)).toList().joinToString("")
        engine.unload()
        println("qwen35-2b: $text")
        assertTrue(text, text.contains("blue", ignoreCase = true))
        assertTrue("No thinking block", !text.contains("<think>"))
    }

    /**
     * A cancelled answer frees the model while its prompt is still being read. Reading thousands of tokens takes
     * minutes on a slow phone, and until the engine lets go, a summary the person asked for waits its turn.
     */
    @Test fun qwenStopsWhileReadingALongPrompt() = runBlocking {
        val (model, folder) = install("qwen35-2b")
        val engine = LlamaLanguageEngine()
        engine.prepare(model, folder)
        val passage = "Ana said the launch moves to March, and Kenji will send the budget on Friday. "
        val request = LanguageRequest("You answer in one short sentence.", passage.repeat(250) + "\nWhen is the launch?", 40)
        val answer = launch(Dispatchers.Default) { engine.generate(request).toList() }
        delay(2000)
        answer.cancel()
        val started = System.nanoTime()
        // Unloading runs after the engine's current work, so it measures how long the prompt kept the model.
        engine.unload()
        val seconds = (System.nanoTime() - started) / 1e9
        println("qwen35-2b: freed $seconds s after cancelling a long prompt")
        assertTrue("Freed after $seconds s", seconds < 30)
    }

    /** A summary's items keep the [seconds] of the line they come from, so each one links to its moment. */
    @Test fun qwenKeepsTheSecondsInASection() = runBlocking {
        val (model, folder) = install("qwen35-2b")
        val engine = LlamaLanguageEngine()
        engine.prepare(model, folder)
        val lines = listOf(
            "[0] Speaker 1: Good morning, thanks for joining the planning call for the spring campaign.",
            "[4] Speaker 2: Happy to be here. I looked at the numbers from last quarter and they look encouraging.",
            "[9] Speaker 1: Great, let us start with the budget, then move to the schedule for the launch.",
            "[14] Speaker 3: Before that, I have a question about the design review. Is it still on Thursday?",
            "[21] Speaker 2: Yes, Thursday at 10. I will send the invitation again after this call.",
            "[25] Speaker 1: Perfect. So, the budget. We have about 20 percent more than last year.",
            "[31] Speaker 3: That is good news. I would put most of it into the video production.",
            "[36] Speaker 2: I agree, but we should keep some for the social media tests in April.",
        )
        val template = com.meetlaud.domain.BuiltInTemplates.all.first()
        val section = template.sections.first()
        val request = com.meetlaud.domain.SummaryPrompts.section(section, template, lines, "en", "en", null)
        val text = engine.generate(request).toList().joinToString("")
        engine.unload()
        println("qwen section (${request.temperature}):\n$text")
        val items = com.meetlaud.domain.SummaryParser.items(text, section.kind)
        // A short meeting goes straight to the sections, which must keep the seconds of the line they cite.
        assertTrue(text, items.mapNotNull { it.sourceTime }.toSet().size > 1)
    }

    @Test fun embeddingsPlaceMeaningAcrossLanguages() = runBlocking {
        val installed = install("qwen3-embedding-0.6b")
        val engine = LlamaEmbeddingEngine { installed }
        val vectors = engine.embed(listOf("The budget was approved.", "O orçamento foi aprovado.", "The cat sleeps on the sofa."), null)
        engine.unload()
        fun cosine(a: List<Float>, b: List<Float>) = a.zip(b).sumOf { (x, y) -> (x * y).toDouble() }
        vectors.forEach { assertEquals(1.0, sqrt(it.sumOf { x -> (x * x).toDouble() }), 1e-3) }
        val same = cosine(vectors[0], vectors[1])
        val other = cosine(vectors[0], vectors[2])
        println("embedding: same meaning $same, different $other")
        assertTrue("$same <= $other", same > other)
    }
}
