package com.meetlaud.app

import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Every screen, in the fictional showcase library, for the parity review with iOS (D-084). Mirrors
 * ios/AppUITests/ParityScreens.swift step for step, by the same identifiers. Run through Tools/parity-screens.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class ParityScreens {
    @get:Rule
    val compose = createEmptyComposeRule()
    private lateinit var scenario: ActivityScenario<MainActivity>
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val folder get() = File(instrumentation.targetContext.getExternalFilesDir(null), "parity").apply { mkdirs() }

    @Before
    fun launch() {
        val intent = Intent(instrumentation.targetContext, MainActivity::class.java).putExtra("showcase", true)
        scenario = ActivityScenario.launch(intent)
    }

    @After
    fun close() {
        scenario.close()
    }

    private fun shoot(name: String) {
        compose.waitForIdle()
        Thread.sleep(1000)
        val bitmap = instrumentation.uiAutomation.takeScreenshot()
        File(folder, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun tap(tag: String) {
        compose.waitUntilAtLeastOneExists(hasTestTag(tag), 5000)
        compose.onNodeWithTag(tag, useUnmergedTree = true).performClick()
    }

    /** The shell and Home: the first screen, and the side menu over it. */
    @Test
    fun testShell() {
        compose.waitUntilAtLeastOneExists(hasTestTag("home.record"), 5000)
        shoot("home")
        tap("drawer.toggle")
        shoot("drawer")
        tap("drawer.item.home")
        tap("home.add")
        shoot("home-add-menu")
    }
}
