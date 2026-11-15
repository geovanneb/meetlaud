package com.meetlaud.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import com.meetlaud.app.routing.DeepLink
import android.os.Bundle
import androidx.compose.runtime.LaunchedEffect
import com.meetlaud.app.feature.shared.LockScreen
import com.meetlaud.app.feature.models.ModelSetupSheet
import com.meetlaud.app.routing.AppRoute
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import com.meetlaud.app.designsystem.MeetlaudTheme
import com.meetlaud.app.feature.recording.RecorderPrompts
import com.meetlaud.app.feature.library.ImportPrompts
import com.meetlaud.app.feature.recording.RecordingPill
import com.meetlaud.app.feature.recording.RecordingScreen
import com.meetlaud.app.feature.shared.LocalPreferences
import com.meetlaud.app.feature.shared.rememberPreference
import com.meetlaud.app.localization.Strings
import com.meetlaud.app.routing.LocalRouter
import com.meetlaud.app.shell.AppShell
import com.meetlaud.domain.AppTheme
import com.meetlaud.domain.ThemePreferences

class MainActivity : ComponentActivity() {
    /** Links go through the router, as onOpenURL does on iOS. Audio from other apps is imported. */
    private fun handle(intent: Intent?) {
        intent ?: return
        val data = intent.data
        when {
            intent.action == Intent.ACTION_VIEW && data?.scheme == DeepLink.SCHEME -> container.router.open(data)
            intent.action == Intent.ACTION_VIEW && data != null -> container.library.importFiles(listOf(data))
            intent.action == Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                (intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))?.let { container.library.importFiles(listOf(it)) }
            }
            intent.action == Intent.ACTION_SEND_MULTIPLE -> {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { container.library.importFiles(it) }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    override fun onDestroy() {
        if (container.authenticator.activity === this) container.authenticator.activity = null
        super.onDestroy()
    }

    private val container: AppContainer get() = (application as MeetlaudApplication).container(intent)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Strings.install(this)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
        )
        val container = container
        container.permissions.attach(this)
        container.authenticator.activity = this
        val composition = Composition(container)
        if (savedInstanceState == null) handle(intent)
        setContent {
            CompositionLocalProvider(LocalRouter provides container.router, LocalPreferences provides container.preferences) {
                val theme = rememberPreference(ThemePreferences.KEY, AppTheme.SYSTEM.raw)
                MeetlaudTheme(AppTheme.from(theme.value)) {
                    AppShell(
                        container.router,
                        content = { composition.screen(it) },
                        routeContent = { composition.screen(it) },
                        accessory = { RecordingPill(container.recorder) },
                        recorder = { RecordingScreen(container.recorder) },
                    )
                    RecorderPrompts(container.recorder)
                    ImportPrompts(container.library)
                    if (container.models.showsSetup) ModelSetupSheet(container.models) { container.router.open(AppRoute.ModelSettings) }
                    LaunchedEffect(Unit) { container.models.offerSetupIfNeeded(container.preferences) }
                    // Above everything, as LockWindow.swift puts its window above the app's.
                    if (container.lock.state.isCovered) LockScreen(container.lock)
                    // The recent apps screen shows a picture of the app. With the lock on, it must not show the library.
                    val isLockEnabled = container.lock.state.isEnabled
                    LaunchedEffect(isLockEnabled) { if (Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(!isLockEnabled) }
                }
            }
        }
    }
}
