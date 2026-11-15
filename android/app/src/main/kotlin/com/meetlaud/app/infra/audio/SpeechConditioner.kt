package com.meetlaud.app.infra.audio

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.tanh

/**
 * Cleans up a window of speech before a model hears it, the same as SpeechConditioner.swift (D-076): a high-pass at
 * 80 Hz, then gentle leveling that raises quiet speech and never raises silence. The file on disk is never changed.
 */
class SpeechConditioner(
    val sampleRate: Double = 16000.0,
    val highPassCutoff: Double = 80.0,
    /** Speech level to aim for, as RMS in dBFS. */
    val targetLevel: Float = -23f,
    /** The most a quiet voice is raised, in dB. */
    val maxGain: Float = 18f,
    /** Frames this far above the noise floor count as speech, in dB. */
    val speechMargin: Float = 9f,
) {
    fun process(samples: FloatArray): FloatArray {
        if (samples.size <= (sampleRate * 0.1).toInt()) return samples
        return level(highPass(samples))
    }

    /** A second-order Butterworth, run once forward. */
    fun highPass(samples: FloatArray): FloatArray {
        val omega = 2 * PI * highPassCutoff / sampleRate
        val alpha = sin(omega) / (2 * 0.7071)
        val cosine = cos(omega)
        val a0 = 1 + alpha
        val b0 = ((1 + cosine) / 2 / a0).toFloat()
        val b1 = (-(1 + cosine) / a0).toFloat()
        val b2 = b0
        val a1 = (-2 * cosine / a0).toFloat()
        val a2 = ((1 - alpha) / a0).toFloat()
        val output = FloatArray(samples.size)
        var x1 = 0f
        var x2 = 0f
        var y1 = 0f
        var y2 = 0f
        for (index in samples.indices) {
            val x0 = samples[index]
            val y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            output[index] = y0
            x2 = x1
            x1 = x0
            y2 = y1
            y1 = y0
        }
        return output
    }

    /** 50 ms frames for measuring, a gain per frame, smoothed, then spread sample by sample. */
    fun level(samples: FloatArray): FloatArray {
        val frame = maxOf(1, (sampleRate * 0.05).toInt())
        val frames = (samples.size + frame - 1) / frame
        val levels = FloatArray(frames) { index ->
            val from = index * frame
            val until = minOf(samples.size, (index + 1) * frame)
            var energy = 0f
            for (i in from until until) energy += samples[i] * samples[i]
            decibels(energy / (until - from))
        }
        // The quietest tenth of the window is taken as the room.
        val floor = levels.sorted()[frames / 10]
        val gate = floor + speechMargin
        // A frame's gain looks at the speech around it (300 ms), so it follows a voice, not a syllable.
        val reach = 3
        val targets = FloatArray(frames) { index ->
            var loudest = Float.NEGATIVE_INFINITY
            for (i in maxOf(0, index - reach)..minOf(frames - 1, index + reach)) loudest = maxOf(loudest, levels[i])
            // No speech nearby leaves the room as it is. A loud voice is never cut.
            if (loudest < gate) 0f else minOf(maxGain, maxOf(0f, targetLevel - loudest))
        }
        // Rises in 200 ms and falls in 50 ms, so that a loud voice right after a quiet one is not blown out.
        val gains = FloatArray(frames)
        var current = 0f
        for (index in 0 until frames) {
            val target = targets[index]
            current += (target - current) * (if (target > current) 0.25f else 1f)
            gains[index] = current
        }
        val output = samples.copyOf()
        for (index in output.indices) {
            val position = index.toFloat() / frame - 0.5f
            val lower = floor(position).toInt().coerceIn(0, frames - 1)
            val upper = minOf(frames - 1, lower + 1)
            val blend = (position - lower).coerceIn(0f, 1f)
            val gain = gains[lower] + (gains[upper] - gains[lower]) * blend
            output[index] = limit(output[index] * linear(gain))
        }
        return output
    }

    companion object {
        fun decibels(power: Float): Float = 10 * log10(maxOf(power, 1e-12f))
        fun linear(decibels: Float): Float = 10f.pow(decibels / 20)

        /** Soft above 0.9, so a raised peak bends instead of clipping into a click. */
        fun limit(sample: Float): Float {
            val magnitude = abs(sample)
            if (magnitude <= 0.9f) return sample
            val bent = 0.9f + 0.1f * tanh((magnitude - 0.9f) / 0.1f)
            return if (sample < 0) -bent else bent
        }
    }
}
