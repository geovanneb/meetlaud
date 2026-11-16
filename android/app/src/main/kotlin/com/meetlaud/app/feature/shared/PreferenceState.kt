package com.meetlaud.app.feature.shared

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.staticCompositionLocalOf
import com.meetlaud.domain.Preferences
import kotlinx.coroutines.launch

/** The app's settings store, for every screen, as UserDefaults.standard. */
val LocalPreferences = staticCompositionLocalOf<Preferences> { error("No preferences") }

/** `@AppStorage` for text: the value, kept in step with the store, and written back when set. */
@Composable
fun rememberPreference(key: String, default: String): MutableState<String> =
    rememberStored(key, { it.string(key) ?: default }) { preferences, value -> preferences.setString(key, value) }

/** `@AppStorage` for a switch. */
@Composable
fun rememberPreference(key: String, default: Boolean): MutableState<Boolean> =
    rememberStored(key, { it.bool(key) ?: default }) { preferences, value -> preferences.setBool(key, value) }

@Composable
fun rememberPreference(key: String, default: Double): MutableState<Double> =
    rememberStored(key, { it.double(key) ?: default }) { preferences, value -> preferences.setDouble(key, value) }

@Composable
private fun <T> rememberStored(key: String, read: (Preferences) -> T, write: (Preferences, T) -> Unit): MutableState<T> {
    val preferences = LocalPreferences.current
    val scope = rememberCoroutineScope()
    val inner = remember(key) { mutableStateOf(read(preferences)) }
    val state = remember(key) {
        object : MutableState<T> by inner {
            override var value: T
                get() = inner.value
                set(value) {
                    inner.value = value
                    write(preferences, value)
                }
        }
    }
    // A change from elsewhere, such as Settings, shows here without being written back.
    DisposableEffect(key) {
        val job = scope.launch { preferences.changes.collect { if (it == key) inner.value = read(preferences) } }
        onDispose { job.cancel() }
    }
    return state
}
