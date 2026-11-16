package com.meetlaud.domain

import kotlin.math.ceil

/**
 * What a person should know before a long transcription starts: how long it should take, and whether the device is
 * in a good state for it.
 */
data class TranscribePlan(
    /** Expected minutes, as a range when the speed is only estimated. Null when nothing is known about the speed. */
    val minutes: IntRange?,
    val rightNow: RightNow,
    val isCharging: Boolean,
) {
    companion object {
        /** A job this long is worth a word first, even when the device is fine. */
        const val LONG_JOB_MINUTES = 10

        operator fun invoke(duration: TimeInterval, speed: SpeedEvidence, rightNow: RightNow, isCharging: Boolean): TranscribePlan {
            val minutes = when (speed) {
                is SpeedEvidence.Measured -> minutes(duration, speed.value)?.let { it..it }
                // The faster speed gives the shorter time.
                is SpeedEvidence.Estimated -> minutes(duration, speed.high)?.let { short ->
                    minutes(duration, speed.low)?.let { short..maxOf(short, it) }
                }
                SpeedEvidence.Unknown -> null
            }
            return TranscribePlan(minutes, rightNow, isCharging)
        }

        private fun minutes(duration: TimeInterval, speed: Double): Int? {
            if (speed <= 0 || duration <= 0) return null
            return maxOf(1, ceil(duration / speed / 60).toInt())
        }
    }

    /** Short jobs on a device in good shape just start. */
    val deservesNote: Boolean get() = rightNow != RightNow.Great || (minutes?.last ?: 0) >= LONG_JOB_MINUTES

    /** Waiting for a charger only helps when there is no charger yet. */
    val canWaitForCharger: Boolean get() = !isCharging
}
