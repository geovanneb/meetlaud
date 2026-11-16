package com.meetlaud.app.feature.recording

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import com.meetlaud.app.designsystem.AlertButton
import com.meetlaud.app.designsystem.IosAlert
import com.meetlaud.app.localization.L10n

/** Consent, permission, and recovery messages, attached once at the root of the app, as RecorderPrompts.swift. */
@Composable
fun RecorderPrompts(controller: RecordingController) {
    val context = LocalContext.current
    if (controller.showsConsent) {
        IosAlert(
            L10n.Recorder.consentTitle, L10n.Recorder.consentMessage,
            listOf(AlertButton(L10n.Common.cancel, AlertButton.Role.CANCEL), AlertButton(L10n.Recorder.consentAccept, tag = "recorder.consent.accept") { controller.acceptConsent() }),
            onDismiss = { controller.showsConsent = false },
        )
    }
    if (controller.showsPermissionDenied) {
        IosAlert(
            L10n.Recorder.permissionTitle, L10n.Recorder.permissionMessage,
            listOf(
                AlertButton(L10n.Common.cancel, AlertButton.Role.CANCEL),
                AlertButton(L10n.Recorder.openSettings) {
                    context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                },
            ),
            onDismiss = { controller.showsPermissionDenied = false },
        )
    }
    if (controller.showsStartFailure) {
        IosAlert(L10n.Recorder.startFailed, null, listOf(AlertButton(L10n.Common.ok, AlertButton.Role.CANCEL)), onDismiss = { controller.showsStartFailure = false })
    }
    if (controller.recoveredCount > 0) {
        IosAlert(L10n.Recorder.recoveredTitle, L10n.Recorder.recoveredMessage, listOf(AlertButton(L10n.Common.ok, AlertButton.Role.CANCEL)), onDismiss = { controller.dismissRecoveryNotice() })
    }
}
