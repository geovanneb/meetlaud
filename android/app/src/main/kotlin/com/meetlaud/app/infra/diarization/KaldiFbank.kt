package com.meetlaud.app.infra.diarization

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min

/**
 * Log mel filter banks as Kaldi computes them, which is what WeSpeaker was trained on: int16 scale, 25 ms frames
 * every 10 ms, DC removal, pre-emphasis 0.97, Hamming window, a 512-point FFT, 80 mel bins from 20 Hz to 8 kHz, no
 * dither, frames cut at the edges. Then the mean over time is taken away, as WeSpeaker does.
 */
object KaldiFbank {
    const val SAMPLE_RATE = 16_000
    const val BINS = 80
    private const val FRAME = 400
    private const val SHIFT = 160
    private const val FFT = 512
    private val window = DoubleArray(FRAME) { 0.54 - 0.46 * cos(2 * PI * it / (FRAME - 1)) }
    private val banks: Array<DoubleArray> = melBanks()
    private val epsilon = Math.ulp(1.0f).toDouble()

    private fun mel(frequency: Double) = 1127.0 * ln(1 + frequency / 700.0)

    private fun melBanks(): Array<DoubleArray> {
        val low = mel(20.0)
        val high = mel(8000.0)
        val step = (high - low) / (BINS + 1)
        return Array(BINS) { bin ->
            val left = low + bin * step
            val center = left + step
            val right = center + step
            DoubleArray(FFT / 2 + 1) { index ->
                if (index == FFT / 2) return@DoubleArray 0.0
                val m = mel(index * SAMPLE_RATE.toDouble() / FFT)
                max(0.0, min((m - left) / (center - left), (right - m) / (right - center)))
            }
        }
    }

    /** One row of 80 values per 10 ms, or an empty array when there is less than one frame. */
    fun compute(samples: FloatArray, count: Int = samples.size): Array<FloatArray> {
        val frames = if (count < FRAME) 0 else 1 + (count - FRAME) / SHIFT
        val result = Array(frames) { FloatArray(BINS) }
        val real = DoubleArray(FFT)
        val imaginary = DoubleArray(FFT)
        val mean = DoubleArray(BINS)
        for (frame in 0 until frames) {
            val offset = frame * SHIFT
            var dc = 0.0
            for (i in 0 until FRAME) dc += samples[offset + i] * 32768.0
            dc /= FRAME
            var previous = samples[offset] * 32768.0 - dc
            for (i in 0 until FRAME) {
                val value = samples[offset + i] * 32768.0 - dc
                // Kaldi pre-emphasizes the first sample against itself.
                real[i] = (value - 0.97 * (if (i == 0) value else previous)) * window[i]
                previous = value
            }
            real.fill(0.0, FRAME, FFT)
            imaginary.fill(0.0)
            Fft.transform(real, imaginary)
            val row = result[frame]
            for (bin in 0 until BINS) {
                val bank = banks[bin]
                var energy = 0.0
                for (k in 0..FFT / 2) {
                    val weight = bank[k]
                    if (weight != 0.0) energy += weight * (real[k] * real[k] + imaginary[k] * imaginary[k])
                }
                val log = ln(max(energy, epsilon))
                row[bin] = log.toFloat()
                mean[bin] += log
            }
        }
        if (frames > 0) for (row in result) for (bin in 0 until BINS) row[bin] -= (mean[bin] / frames).toFloat()
        return result
    }
}

/** An in-place radix-2 FFT, for the one size the filter banks need. */
internal object Fft {
    fun transform(real: DoubleArray, imaginary: DoubleArray) {
        val n = real.size
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) {
                j = j xor bit
                bit = bit shr 1
            }
            j = j xor bit
            if (i < j) {
                real[i] = real[j].also { real[j] = real[i] }
                imaginary[i] = imaginary[j].also { imaginary[j] = imaginary[i] }
            }
        }
        var length = 2
        while (length <= n) {
            val angle = -2 * PI / length
            val stepReal = cos(angle)
            val stepImaginary = kotlin.math.sin(angle)
            var start = 0
            while (start < n) {
                var wReal = 1.0
                var wImaginary = 0.0
                for (k in 0 until length / 2) {
                    val a = start + k
                    val b = a + length / 2
                    val tReal = real[b] * wReal - imaginary[b] * wImaginary
                    val tImaginary = real[b] * wImaginary + imaginary[b] * wReal
                    real[b] = real[a] - tReal
                    imaginary[b] = imaginary[a] - tImaginary
                    real[a] += tReal
                    imaginary[a] += tImaginary
                    val next = wReal * stepReal - wImaginary * stepImaginary
                    wImaginary = wReal * stepImaginary + wImaginary * stepReal
                    wReal = next
                }
                start += length
            }
            length = length shl 1
        }
    }
}
