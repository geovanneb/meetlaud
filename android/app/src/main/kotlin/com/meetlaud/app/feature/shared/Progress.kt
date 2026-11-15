package com.meetlaud.app.feature.shared

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.meetlaud.app.designsystem.ProcessStep
import com.meetlaud.app.designsystem.ProcessStepLabels
import com.meetlaud.app.designsystem.StatusBadge
import com.meetlaud.app.designsystem.Tone
import com.meetlaud.app.localization.L10n
import com.meetlaud.domain.JobProgress
import com.meetlaud.domain.RecordingSort
import com.meetlaud.domain.RightNow
import java.text.NumberFormat
import com.meetlaud.app.localization.Strings

/** "42%", in the interface's language. */
fun percent(fraction: Double): String = NumberFormat.getPercentInstance(Strings.locale()).apply { maximumFractionDigits = 0 }.format(fraction)

val JobProgress.statusText: String
    get() = when (phase) {
        JobProgress.Phase.QUEUED -> L10n.Transcript.queued
        JobProgress.Phase.PREPARING -> L10n.Transcript.preparing
        JobProgress.Phase.TRANSCRIBING -> L10n.Transcript.transcribing(percent(fraction))
        JobProgress.Phase.SEPARATING_SPEAKERS -> L10n.Transcript.separatingSpeakers
        JobProgress.Phase.WAITING_FOR_DEVICE -> L10n.Transcript.waitingForDevice
        JobProgress.Phase.WAITING_FOR_POWER -> L10n.Transcript.waitingForPower
        JobProgress.Phase.INTERRUPTED -> L10n.Transcript.interrupted
    }

val standardStepLabels: ProcessStepLabels
    get() = ProcessStepLabels(L10n.Feedback.stepWaiting, L10n.Feedback.stepActive, L10n.Feedback.stepDone)

/** The steps of a transcription, with where this job is. */
val JobProgress.steps: List<ProcessStep>
    get() {
        val order = mutableListOf(
            ProcessStep("prepare", L10n.Transcript.stepPrepare, ProcessStep.State.WAITING) to JobProgress.Phase.PREPARING,
            ProcessStep("transcribe", L10n.Transcript.stepTranscribe, ProcessStep.State.WAITING) to JobProgress.Phase.TRANSCRIBING,
        )
        if (includesSpeakers) order.add(ProcessStep("speakers", L10n.Transcript.stepSpeakers, ProcessStep.State.WAITING) to JobProgress.Phase.SEPARATING_SPEAKERS)
        val current = order.indexOfFirst { it.second == phase }.takeIf { it >= 0 }
        return order.mapIndexed { index, entry ->
            val state = when {
                current == null -> ProcessStep.State.WAITING
                index < current -> ProcessStep.State.DONE
                index == current -> ProcessStep.State.ACTIVE
                else -> ProcessStep.State.WAITING
            }
            entry.first.copy(state = state)
        }
    }

/** A badge for a list row: a ring that fills while text is being written, and a symbol while waiting. */
@Composable
fun ProgressBadge(progress: JobProgress, modifier: Modifier = Modifier) {
    when (progress.phase) {
        JobProgress.Phase.TRANSCRIBING -> StatusBadge(progress.statusText, Tone.WORKING, modifier, fraction = progress.fraction)
        JobProgress.Phase.PREPARING, JobProgress.Phase.SEPARATING_SPEAKERS -> StatusBadge(progress.statusText, Tone.WORKING, modifier)
        JobProgress.Phase.QUEUED -> StatusBadge(progress.statusText, Tone.WAITING, modifier, symbol = "hourglass")
        JobProgress.Phase.WAITING_FOR_DEVICE -> StatusBadge(progress.statusText, Tone.ATTENTION, modifier, symbol = "thermometer.medium")
        JobProgress.Phase.WAITING_FOR_POWER -> StatusBadge(progress.statusText, Tone.ATTENTION, modifier, symbol = "bolt.fill")
        JobProgress.Phase.INTERRUPTED -> StatusBadge(progress.statusText, Tone.ATTENTION, modifier, symbol = "exclamationmark.triangle.fill")
    }
}

val RecordingSort.title: String
    get() = when (this) {
        RecordingSort.NEWEST -> L10n.Library.sortNewest
        RecordingSort.OLDEST -> L10n.Library.sortOldest
        RecordingSort.NAME -> L10n.Library.sortName
        RecordingSort.LONGEST -> L10n.Library.sortLongest
    }

/** One stored choice, so that Home and Library stay in the same order. */
const val RECORDING_SORT_KEY = "library.sort"

/** The device status in the same words on every screen. */
val RightNow.title: String
    get() = when (this) {
        RightNow.Great -> L10n.Models.nowGreat
        is RightNow.Good -> L10n.Models.nowGood
        is RightNow.Limited -> L10n.Models.nowLimited
        RightNow.Paused -> L10n.Models.nowPaused
    }

val RightNow.detail: String?
    get() {
        val reason = when (this) {
            is RightNow.Good -> reason
            is RightNow.Limited -> reason
            else -> return null
        }
        return when (reason) {
            RightNow.Reason.WARM -> L10n.Models.conditionWarm
            RightNow.Reason.HOT -> L10n.Models.conditionHot
            RightNow.Reason.LOW_POWER -> L10n.Models.conditionLowPower
            RightNow.Reason.LOW_BATTERY -> L10n.Models.conditionLowBattery
            RightNow.Reason.LOW_MEMORY -> L10n.Models.conditionLowMemory
        }
    }
