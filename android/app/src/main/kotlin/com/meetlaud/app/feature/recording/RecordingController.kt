package com.meetlaud.app.feature.recording

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.meetlaud.app.designsystem.abbreviatedDateTime
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.routing.AppRoute
import com.meetlaud.app.routing.AppRouter
import com.meetlaud.domain.AudioInput
import com.meetlaud.domain.CaptureStatus
import com.meetlaud.domain.MarkerKind
import com.meetlaud.domain.MicrophoneAccess
import com.meetlaud.domain.MicrophonePermission
import com.meetlaud.domain.Preferences
import com.meetlaud.domain.RecordingCoordinator
import com.meetlaud.domain.RecordingID
import com.meetlaud.domain.RecordingSnapshot
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.time.Instant

/** Connects the recording screens to the coordinator. There is one for the life of the app, as RecordingController.swift. */
class RecordingController(
    private val coordinator: RecordingCoordinator,
    private val permission: MicrophonePermission,
    private val router: AppRouter,
    private val defaults: Preferences,
    private val scope: CoroutineScope,
) {
    var snapshot by mutableStateOf(RecordingSnapshot())
        private set
    var levels by mutableStateOf<List<Float>>(emptyList())
        private set
    var inputs by mutableStateOf<List<AudioInput>>(emptyList())
        private set
    var recoveredCount by mutableStateOf(0)
        private set
    var showsConsent by mutableStateOf(false)
    var showsPermissionDenied by mutableStateOf(false)
    var showsStartFailure by mutableStateOf(false)

    private var pendingTitle: String? = null
    private var pendingAttendees: List<String> = emptyList()

    /** Called with each finished recording, so that the rest of the app can react. */
    var onSaved: ((RecordingID) -> Unit)? = null
    /** Called when capture starts and ends. Anything heavy has to step aside for it. */
    var onActivityChanged: ((Boolean) -> Unit)? = null

    companion object {
        const val CONSENT_KEY = "recorder.hasSeenConsent"
        private const val MAXIMUM_LEVELS = 200
    }

    init {
        scope.launch { coordinator.snapshots.collect { apply(it) } }
    }

    private fun apply(next: RecordingSnapshot) {
        if (next.status == CaptureStatus.Recording && next.recorded != snapshot.recorded) {
            levels = (levels + next.level).takeLast(MAXIMUM_LEVELS)
        }
        val wasActive = snapshot.status.isActive
        snapshot = next
        if (next.status.isActive != wasActive) onActivityChanged?.invoke(next.status.isActive)
    }

    // MARK: - Start

    fun record(title: String? = null, attendees: List<String> = emptyList()) {
        pendingTitle = title
        pendingAttendees = attendees
        if (snapshot.status.isActive) {
            router.isRecorderPresented = true
            return
        }
        if (defaults.bool(CONSENT_KEY) != true) {
            showsConsent = true
            return
        }
        scope.launch { start() }
    }

    fun acceptConsent() {
        defaults.setBool(CONSENT_KEY, true)
        showsConsent = false
        scope.launch { start() }
    }

    private suspend fun start() {
        when (permission.access) {
            MicrophoneAccess.GRANTED -> {}
            // Android lets an app ask again after a first no, so a denial is final only when the second ask fails.
            MicrophoneAccess.DENIED, MicrophoneAccess.UNDETERMINED -> if (!permission.request()) {
                showsPermissionDenied = true
                return
            }
        }
        // Show the screen first, so that the tap gets an instant answer.
        router.isRecorderPresented = true
        val title = pendingTitle ?: L10n.Recorder.defaultTitle(Instant.now().abbreviatedDateTime())
        try {
            coordinator.start(title, pendingAttendees)
            inputs = coordinator.availableInputs()
        } catch (_: Exception) {
            showsStartFailure = true
        }
    }

    // MARK: - Controls

    fun togglePause() {
        scope.launch {
            if (snapshot.status is CaptureStatus.Paused) runCatching { coordinator.resume() } else coordinator.pause()
        }
    }

    fun stop() {
        scope.launch {
            val saved = runCatching { coordinator.stop() }.getOrNull()
            router.isRecorderPresented = false
            levels = emptyList()
            if (saved != null) {
                router.push(AppRoute.Recording(saved.id))
                onSaved?.invoke(saved.id)
            }
        }
    }

    fun flag() {
        scope.launch { runCatching { coordinator.addMarker(MarkerKind.FLAG) } }
    }

    fun addNote(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        scope.launch { runCatching { coordinator.addMarker(MarkerKind.NOTE, trimmed) } }
    }

    fun addPhoto(data: ByteArray) {
        scope.launch { runCatching { coordinator.addPhoto(data) } }
    }

    fun select(input: AudioInput) {
        scope.launch { runCatching { coordinator.selectInput(input) } }
    }

    // MARK: - Recovery

    fun recover() {
        scope.launch { recoveredCount = runCatching { coordinator.recoverInterrupted() }.getOrDefault(emptyList()).size }
    }

    fun dismissRecoveryNotice() {
        recoveredCount = 0
    }
}
