package com.meetlaud.app

import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.meetlaud.app.feature.recording.RecordingController
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.routing.AppRoute
import com.meetlaud.app.routing.Destination
import org.junit.After
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * The Google Play screenshots, from the fictional showcase library in the app's current language. The counterpart of
 * ios/AppUITests/ScreenshotTests.swift. Runs only when asked, through docs/store/make-screenshots, which sets the
 * language, a clean status bar, and the models the showcase shows as installed.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class StoreScreenshots {
    @get:Rule
    val compose = createEmptyComposeRule()
    private lateinit var scenario: ActivityScenario<MainActivity>
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val folder get() = File(instrumentation.targetContext.getExternalFilesDir(null), "store").apply { mkdirs() }
    private val container get() = (instrumentation.targetContext.applicationContext as MeetlaudApplication).container(null)

    @Before
    fun launch() {
        assumeTrue("Pass -e storeScreenshots true to take the store screenshots", InstrumentationRegistry.getArguments().getString("storeScreenshots") == "true")
        val intent = Intent(instrumentation.targetContext, MainActivity::class.java).putExtra("showcase", true)
        scenario = ActivityScenario.launch(intent)
        container.preferences.setBool(RecordingController.CONSENT_KEY, true)
    }

    @After
    fun close() {
        if (::scenario.isInitialized) scenario.close()
    }

    private fun shoot(name: String, settle: Long = 1200) {
        compose.waitForIdle()
        Thread.sleep(settle)
        val bitmap = instrumentation.uiAutomation.takeScreenshot()
        File(folder, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private val regions = mutableMapOf<String, List<Int>>()

    /**
     * Where every node with this tag sits on the screen, together, in pixels: the store pictures enlarge that part.
     * Written next to the screenshots as regions.json, as {"name": [left, top, right, bottom]}.
     */
    private fun region(name: String, tag: String, skip: Int = 0, first: Int = Int.MAX_VALUE, wide: Boolean = false, above: Int = 0) {
        val screen = instrumentation.targetContext.resources.displayMetrics
        // Only what is on screen, whole: a node scrolled away reports a sliver at the edge.
        val bounds = compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().map { it.boundsInWindow }
            .filter { it.top > 0 && it.bottom < screen.heightPixels && it.height > 8 }.drop(skip).take(first)
        if (bounds.isEmpty()) return
        // A tag on a small part of a row, such as a timestamp, stands for the whole row, between the screen's margins.
        val gutter = 16 * screen.density
        val left = if (wide) gutter else bounds.minOf { it.left }
        val right = if (wide) screen.widthPixels - gutter else bounds.maxOf { it.right }
        val top = bounds.minOf { it.top } - above * screen.density
        regions[name] = listOf(left, top, right, bounds.maxOf { it.bottom } + 6 * screen.density).map { it.toInt() }
        File(folder, "regions.json").writeText(
            regions.entries.joinToString(",\n", "{\n", "\n}\n") { (key, value) -> "  \"$key\": [${value.joinToString()}]" },
        )
    }

    private fun waitFor(tag: String) = compose.waitUntilAtLeastOneExists(hasTestTag(tag), 10_000)

    private fun tap(tag: String) {
        waitFor(tag)
        compose.onNodeWithTag(tag, useUnmergedTree = true).performClick()
    }

    private fun main(block: () -> Unit) = instrumentation.runOnMainSync(block)

    @Test
    fun takeScreenshots() {
        waitFor("home.record")
        shoot("01-home")

        waitFor("recording.row")
        compose.onAllNodesWithTag("recording.row", useUnmergedTree = true).onFirst().performClick()
        waitFor("screen.detail")
        tap("tab.summary")
        waitFor("summary.task")
        shoot("03-summary")
        region("summary", "summary.source", skip = 3, first = 2, wide = true, above = 44)

        tap("tab.transcript")
        waitFor("speaker.chip")
        shoot("02-transcript")
        region("transcript", "transcript.segment", first = 2)

        // The seeded chat about this meeting, with its sources.
        tap("detail.ask")
        waitFor("ask.citation")
        shoot("04-ask")
        region("ask", "ask.citation")

        main { container.router.open(AppRoute.ModelSettings) }
        waitFor("screen.models")
        shoot("06-models")

        main { container.router.select(Destination.TOOLS) }
        waitFor("tools.tabs")
        compose.waitUntilAtLeastOneExists(hasText(L10n.Tools.templates), 5000)
        compose.onNodeWithText(L10n.Tools.templates).performClick()
        waitFor("template.card")
        shoot("07-templates")

        main { container.router.open(AppRoute.NetworkActivity) }
        waitFor("screen.network")
        shoot("08-network")

        main {
            container.router.select(Destination.HOME)
            container.router.setPath(emptyList(), Destination.HOME)
        }
        tap("home.record")
        waitFor("recorder.stop")
        // Long enough for the level meter to fill the screen. waitUntil keeps frames coming, where a sleep would
        // freeze the screen. The showcase engine records nothing, so there is nothing to save: closing the app ends it.
        compose.waitUntil(40_000) { container.recordingCoordinator.currentSnapshot.recorded >= 24.0 }
        shoot("05-recording", settle = 300)
    }
}
