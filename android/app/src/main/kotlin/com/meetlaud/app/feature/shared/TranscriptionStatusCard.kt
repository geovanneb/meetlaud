package com.meetlaud.app.feature.shared

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import com.meetlaud.app.designsystem.ActivityBar
import com.meetlaud.app.designsystem.ControlSize
import com.meetlaud.app.designsystem.Ds
import com.meetlaud.app.designsystem.DsType
import com.meetlaud.app.designsystem.SecondaryAction
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.designsystem.StatusBadge
import com.meetlaud.app.designsystem.StepList
import com.meetlaud.app.designsystem.Tone
import com.meetlaud.app.designsystem.dsCard
import com.meetlaud.app.localization.L10n
import com.meetlaud.app.localization.Strings
import com.meetlaud.domain.JobProgress
import kotlinx.coroutines.delay
import java.time.Duration
import java.time.Instant

/**
 * What a meeting's transcription is doing, while it runs, as TranscriptionStatusCard.swift: the steps, a bar that
 * fills when the fraction is real and keeps moving when it is not, the time that passed, and the time left once it
 * can be measured.
 */
@Composable
fun TranscriptionStatusCard(progress: JobProgress, modifier: Modifier = Modifier, onCancel: () -> Unit) {
    val waiting = when (progress.phase) {
        JobProgress.Phase.QUEUED -> Triple(L10n.Transcript.queued, Tone.WAITING, "hourglass")
        JobProgress.Phase.WAITING_FOR_DEVICE -> Triple(L10n.Transcript.waitingForDevice, Tone.ATTENTION, "thermometer.medium")
        JobProgress.Phase.WAITING_FOR_POWER -> Triple(L10n.Transcript.waitingForPower, Tone.ATTENTION, "bolt.fill")
        JobProgress.Phase.INTERRUPTED -> Triple(L10n.Transcript.interrupted, Tone.ATTENTION, "exclamationmark.triangle.fill")
        else -> null
    }
    val note = when (progress.phase) {
        JobProgress.Phase.QUEUED -> L10n.Transcript.queuedNote
        JobProgress.Phase.WAITING_FOR_DEVICE -> L10n.Transcript.deviceNote
        JobProgress.Phase.WAITING_FOR_POWER -> L10n.Transcript.powerNote
        JobProgress.Phase.INTERRUPTED -> L10n.Transcript.interruptedNote
        JobProgress.Phase.PREPARING -> L10n.Transcript.prepareNote
        JobProgress.Phase.SEPARATING_SPEAKERS -> L10n.Transcript.speakersNote
        JobProgress.Phase.TRANSCRIBING -> L10n.Transcript.leaveNote
    }
    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1000)
            now = Instant.now()
        }
    }
    Column(modifier.dsCard().testTag("transcript.status"), verticalArrangement = Arrangement.spacedBy(Spacing.compact)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(L10n.Transcript.workingTitle, style = DsType.heading, color = Ds.primaryText.value, modifier = Modifier.weight(1f).semantics { heading() })
            Spacer(Modifier.width(Spacing.small))
            if (progress.isMeasurable) Text(percent(progress.fraction), style = DsType.meta.copy(fontFeatureSettings = "tnum"), color = Ds.primaryText.value)
        }
        if (waiting != null) StatusBadge(waiting.first, waiting.second, symbol = waiting.third) else ActivityBar(if (progress.isMeasurable) progress.fraction else null)
        StepList(progress.steps, standardStepLabels)
        timing(progress, waiting != null, now)?.let { Text(it, style = DsType.note.copy(fontFeatureSettings = "tnum"), color = Ds.secondaryText.value) }
        Text(note, style = DsType.note, color = Ds.secondaryText.value)
        SecondaryAction(L10n.Common.cancel, Modifier.testTag("transcript.cancel"), ControlSize.REGULAR, onClick = onCancel)
    }
}

/** Elapsed time, and the time left once it can be measured. Nothing while waiting: no work is going on. */
private fun timing(progress: JobProgress, isWaiting: Boolean, now: Instant): String? {
    if (isWaiting) return null
    val started = progress.phaseStartedAt ?: return null
    val elapsed = L10n.Feedback.elapsed(abbreviatedDuration(Duration.between(started, now).seconds.toDouble()))
    val left = progress.estimatedRemaining(now) ?: return elapsed
    return listOf(elapsed, L10n.Feedback.remaining(abbreviatedDuration(left))).joinToString(" · ")
}

/** "1 hr, 5 min" or "42 sec", at most two units, as Duration's abbreviated units style. */
fun abbreviatedDuration(seconds: Double): String {
    val total = maxOf(0L, Math.round(seconds))
    val units = android.icu.text.MeasureFormat.getInstance(Strings.locale(), android.icu.text.MeasureFormat.FormatWidth.SHORT)
    val hours = total / 3600
    val minutes = total % 3600 / 60
    val rest = total % 60
    val parts = mutableListOf<android.icu.util.Measure>()
    if (hours > 0) parts += android.icu.util.Measure(hours, android.icu.util.MeasureUnit.HOUR)
    if (minutes > 0) parts += android.icu.util.Measure(minutes, android.icu.util.MeasureUnit.MINUTE)
    if (rest > 0 || parts.isEmpty()) parts += android.icu.util.Measure(rest, android.icu.util.MeasureUnit.SECOND)
    return units.formatMeasures(*parts.take(2).toTypedArray())
}
