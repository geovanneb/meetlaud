package com.meetlaud.app.feature.models

import com.meetlaud.app.designsystem.fileSize
import com.meetlaud.app.feature.shared.languageName
import com.meetlaud.app.localization.L10n
import com.meetlaud.domain.AdvisorSuggestion
import com.meetlaud.domain.FitLabel
import com.meetlaud.domain.FitReason
import com.meetlaud.domain.InstallFailure
import com.meetlaud.domain.InstallState
import com.meetlaud.domain.ModelRole
import com.meetlaud.domain.ModelsSnapshot
import com.meetlaud.domain.Priority
import com.meetlaud.domain.SpeedEvidence
import kotlin.math.roundToInt

/** The words for the model types, as ModelFormatting.swift. */
val ModelRole.title: String
    get() = when (this) {
        ModelRole.TRANSCRIPTION -> L10n.Models.roleTranscription
        ModelRole.SPEAKER_SEPARATION -> L10n.Models.roleSpeakers
        ModelRole.VOICE_PRINT -> L10n.Models.roleVoicePrint
        ModelRole.CHAT -> L10n.Models.roleChat
        ModelRole.SEARCH -> L10n.Models.roleSearch
    }

val ModelRole.purpose: String
    get() = when (this) {
        ModelRole.TRANSCRIPTION -> L10n.Models.purposeTranscription
        ModelRole.SPEAKER_SEPARATION -> L10n.Models.purposeSpeakers
        ModelRole.VOICE_PRINT -> L10n.Models.purposeVoicePrint
        ModelRole.CHAT -> L10n.Models.purposeChat
        ModelRole.SEARCH -> L10n.Models.purposeSearch
    }

val FitLabel.title: String
    get() = when (this) {
        FitLabel.BEST -> L10n.Models.fitBest
        FitLabel.GOOD -> L10n.Models.fitGood
        FitLabel.MAY_SLOW -> L10n.Models.fitSlow
        FitLabel.NOT_RECOMMENDED -> L10n.Models.fitNotRecommended
        FitLabel.UNSUPPORTED -> L10n.Models.fitUnsupported
    }

val FitReason.title: String
    get() = when (this) {
        FitReason.BestForDevice -> L10n.Models.reasonBest
        FitReason.WorksWell -> L10n.Models.reasonWorks
        FitReason.BelowTargetSpeed -> L10n.Models.reasonSlow
        FitReason.NotEnoughMemory -> L10n.Models.reasonMemory
        FitReason.UnstableHere -> L10n.Models.reasonUnstable
        is FitReason.LanguageNotCovered -> L10n.Models.reasonLanguage(languageName(language))
    }

/** Plain words: nobody thinks in multiples of real time. */
val SpeedEvidence.title: String
    get() = when (this) {
        is SpeedEvidence.Measured -> L10n.Models.speedMeasured(minutes(value))
        is SpeedEvidence.Estimated -> L10n.Models.speedEstimated(minutes(high), minutes(low))
        SpeedEvidence.Unknown -> L10n.Models.speedUnknown
    }

private fun minutes(speed: Double): Int = if (speed <= 0) 0 else maxOf(1, (60 / speed).roundToInt())

fun AdvisorSuggestion.title(snapshot: ModelsSnapshot): String {
    fun name(id: String) = snapshot.fits.values.flatten().firstOrNull { it.model.id == id }?.model?.displayName ?: id
    return when (this) {
        is AdvisorSuggestion.BetterFit -> L10n.Models.suggestBetter(name(modelID))
        is AdvisorSuggestion.LanguageNotCovered -> L10n.Models.suggestLanguage(languageName(language))
        is AdvisorSuggestion.Unstable -> L10n.Models.suggestUnstable(name(modelID))
        is AdvisorSuggestion.TooSlow -> L10n.Models.suggestSlow(name(modelID))
        is AdvisorSuggestion.UnusedModel -> L10n.Models.suggestUnused(name(modelID), bytes.fileSize)
    }
}

val Priority.title: String
    get() = when (this) {
        Priority.SPEED -> L10n.Models.prioritySpeed
        Priority.BALANCED -> L10n.Models.priorityBalanced
        Priority.QUALITY -> L10n.Models.priorityQuality
    }

/** Anything between asking for a model and having it. Steps with no fraction still move on screen. */
val InstallState.isWorking: Boolean
    get() = when (this) {
        InstallState.Queued, is InstallState.Downloading, InstallState.Verifying, InstallState.Preparing, InstallState.SelfTest -> true
        else -> false
    }

val InstallState.progress: Double?
    get() = when (this) {
        is InstallState.Downloading -> if (total > 0) received.toDouble() / total else 0.0
        is InstallState.Paused -> if (total > 0) received.toDouble() / total else 0.0
        else -> null
    }

val InstallState.title: String?
    get() = when (this) {
        InstallState.NotInstalled -> null
        InstallState.Queued -> L10n.Models.stateQueued
        is InstallState.Downloading -> L10n.Models.stateDownloading(received.fileSize, total.fileSize)
        is InstallState.Paused -> L10n.Models.statePaused
        InstallState.WaitingForWiFi -> L10n.Models.stateWaitingWiFi
        InstallState.Verifying -> L10n.Models.stateVerifying
        InstallState.Preparing -> L10n.Models.statePreparing
        InstallState.SelfTest -> L10n.Models.stateTesting
        InstallState.Ready -> L10n.Models.stateReady
        is InstallState.Failed -> when (failure) {
            InstallFailure.NO_SPACE -> L10n.Models.failedSpace
            InstallFailure.DAMAGED -> L10n.Models.failedDamaged
            InstallFailure.UNAVAILABLE -> L10n.Models.failedUnavailable
            InstallFailure.PREPARE_FAILED -> L10n.Models.failedPrepare
        }
    }
