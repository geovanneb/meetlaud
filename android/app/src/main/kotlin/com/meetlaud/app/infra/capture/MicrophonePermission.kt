package com.meetlaud.app.infra.capture

import android.Manifest
import android.os.Build
import com.meetlaud.app.infra.system.Permissions
import com.meetlaud.domain.MicrophoneAccess
import com.meetlaud.domain.MicrophonePermission

/** The microphone, and on Android 13 and later the notification that shows a recording is on. */
class LiveMicrophonePermission(private val permissions: Permissions) : MicrophonePermission {
    override val access: MicrophoneAccess
        get() = when {
            permissions.isGranted(Manifest.permission.RECORD_AUDIO) -> MicrophoneAccess.GRANTED
            permissions.wasAsked(Manifest.permission.RECORD_AUDIO) -> MicrophoneAccess.DENIED
            else -> MicrophoneAccess.UNDETERMINED
        }

    override suspend fun request(): Boolean {
        val asked = if (Build.VERSION.SDK_INT >= 33) {
            arrayOf(Manifest.permission.RECORD_AUDIO, Manifest.permission.POST_NOTIFICATIONS)
        } else {
            arrayOf(Manifest.permission.RECORD_AUDIO)
        }
        permissions.request(*asked)
        // The notification is a courtesy; the microphone is what recording needs.
        return permissions.isGranted(Manifest.permission.RECORD_AUDIO)
    }
}
