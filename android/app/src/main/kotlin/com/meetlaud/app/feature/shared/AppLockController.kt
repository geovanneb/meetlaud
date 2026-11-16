package com.meetlaud.app.feature.shared

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.IconSize
import com.meetlaud.app.designsystem.PrimaryAction
import com.meetlaud.app.designsystem.SfIcon
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.localization.L10n
import com.meetlaud.domain.AppLockPreferences
import com.meetlaud.domain.AppLockState
import com.meetlaud.domain.DeviceAuthenticator
import com.meetlaud.domain.Preferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** Whether the screen is covered right now, for the life of the app, as AppLockController.swift (D-061). */
class AppLockController(private val defaults: Preferences, private val authenticator: DeviceAuthenticator, private val reason: () -> String, private val scope: CoroutineScope) {
    // A screen lock removed in Settings would otherwise leave the app locked for good, and the library out of reach.
    var state by mutableStateOf(AppLockState(isEnabled = defaults.bool(AppLockPreferences.ENABLED_KEY) == true && authenticator.isAvailable))
        private set

    val canLock: Boolean get() = authenticator.isAvailable

    suspend fun setEnabled(enabled: Boolean): Boolean {
        // Proves the person can open it again, and that the one turning it off is the owner.
        if (!authenticator.isAvailable || !authenticator.authenticate(reason())) return false
        state = state.setEnabled(enabled)
        defaults.setBool(AppLockPreferences.ENABLED_KEY, enabled)
        return true
    }

    /** For erasing everything, where the preference is already gone. */
    fun forgetLock() {
        state = state.setEnabled(false)
    }

    fun becameInactive() {
        state = state.becameInactive()
    }

    fun enteredBackground() {
        state = state.enteredBackground()
    }

    fun becameActive() {
        val (next, ask) = state.becameActive()
        state = next
        if (ask) scope.launch { authenticate() }
    }

    fun unlock() {
        val (next, ask) = state.requestUnlock()
        state = next
        if (ask) scope.launch { authenticate() }
    }

    private suspend fun authenticate() {
        val success = authenticator.authenticate(reason())
        state = state.finishAuthentication(success)
    }
}

/** Hides everything: from the recent apps screen, and from anyone holding an unlocked phone. */
@Composable
fun LockScreen(controller: AppLockController) {
    Column(
        Modifier.fillMaxSize().background(Ds.background.value).padding(Spacing.large).testTag("screen.lock"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.medium, Alignment.CenterVertically),
    ) {
        SfIcon("lock.fill", tint = Ds.secondaryText.value, size = IconSize.hero)
        if (controller.state.isLocked) {
            Text(L10n.System.lockedTitle, style = DsType.sectionTitle, color = Ds.primaryText.value)
            PrimaryAction(L10n.System.unlock, Modifier.testTag("lock.unlock"), onClick = controller::unlock)
        }
    }
}
