package com.meetlaud.app.feature.recording

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.LocalDarkTheme
import com.meetlaud.app.designsystem.PlainButton
import com.meetlaud.app.designsystem.PromptMetrics
import com.meetlaud.app.designsystem.SfIcon
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.designsystem.TapTarget
import com.meetlaud.app.designsystem.clock
import com.meetlaud.app.designsystem.glass
import com.meetlaud.app.designsystem.promptPlacement
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.routing.LocalRouter
import com.meetlaud.domain.CaptureStatus

/** Shows the recording in progress on every screen, once the recorder is minimized, as RecordingPill.swift. */
@Composable
fun RecordingPill(controller: RecordingController) {
    val router = LocalRouter.current
    val snapshot = controller.snapshot
    val isPaused = snapshot.status is CaptureStatus.Paused
    val haptics = LocalHapticFeedback.current
    AnimatedVisibility(snapshot.status.isActive && !router.isRecorderPresented, enter = fadeIn() + slideInVertically { it / 4 }, exit = fadeOut() + slideOutVertically { it / 4 }) {
        Row(
            Modifier.promptPlacement().fillMaxWidth().defaultMinSize(minHeight = PromptMetrics.minimumHeight).glass(CircleShape, LocalDarkTheme.current).clip(CircleShape),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            PlainButton(
                {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    router.isRecorderPresented = true
                },
                Modifier.weight(1f).testTag("recorder.pill").padding(start = PromptMetrics.textInset).defaultMinSize(minHeight = PromptMetrics.minimumHeight),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.small)) {
                    Box(Modifier.size(10.dp).clip(CircleShape).background(if (isPaused) Ds.secondaryText.value else Ds.record.value))
                    Text(snapshot.recorded.clock, style = DsType.rowTitle.copy(fontFeatureSettings = "tnum"), color = Ds.primaryText.value)
                    Text(if (isPaused) L10n.Recorder.statusPaused else L10n.Recorder.statusRecording, style = DsType.meta, color = Ds.secondaryText.value)
                }
                Spacer(Modifier.weight(1f))
            }
            PlainButton({ controller.togglePause() }, Modifier.padding(end = Spacing.compact).size(TapTarget), label = if (isPaused) L10n.Recorder.resume else L10n.Recorder.pause) {
                Spacer(Modifier.weight(1f))
                SfIcon(if (isPaused) "play.fill" else "pause.fill")
                Spacer(Modifier.weight(1f))
            }
        }
    }
}
