package com.meetlaud.app.feature.shared

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import com.meetlaud.app.designsystem.Motion
import com.meetlaud.app.designsystem.RowLabel
import com.meetlaud.app.designsystem.Spacing
import com.meetlaud.app.designsystem.abbreviatedDateTime
import com.meetlaud.app.designsystem.clock
import com.meetlaud.app.designsystem.shortTime
import com.meetlaud.app.localization.L10n
import com.meetlaud.domain.JobProgress
import com.meetlaud.domain.Recording
import com.meetlaud.domain.RecordingStatus

/** One line for a recording, the same everywhere it appears. */
@Composable
fun RecordingRow(recording: Recording, modifier: Modifier = Modifier, progress: JobProgress? = null, showsDay: Boolean = true) {
    Column(
        modifier.fillMaxWidth().padding(vertical = Spacing.xSmall).semantics(mergeDescendants = true) {}.testTag("recording.row"),
        verticalArrangement = Arrangement.spacedBy(Spacing.xSmall),
    ) {
        RowLabel(recording.title, recordingDetail(recording, showsDay))
        AnimatedVisibility(progress != null, enter = fadeIn(Motion.standard()), exit = fadeOut(Motion.standard())) {
            if (progress != null) ProgressBadge(progress)
        }
    }
}

fun recordingDetail(recording: Recording, showsDay: Boolean = true): String {
    val parts = mutableListOf(if (showsDay) recording.createdAt.abbreviatedDateTime() else recording.createdAt.shortTime())
    parts.add(if (recording.status == RecordingStatus.CAPTURING) L10n.Recorder.statusRecording else recording.duration.clock)
    if (recording.wasRecovered) parts.add(L10n.Recorder.recovered)
    return parts.joinToString(" · ")
}
