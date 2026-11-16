package com.meetlaud.app.infra.audio

import com.meetlaud.domain.AudioWindow
import com.meetlaud.domain.AudioWindowSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Reads audio as windows at 16 kHz mono, so that memory stays flat however long the meeting, as
 * SpeechWindowReader.swift (D-034). Windows end at the quietest moment near the boundary, so as not to cut a word, and
 * a window is read only when the one before it was taken.
 */
class SpeechWindowReader(
    private val windowDuration: Double = 180.0,
    private val searchDuration: Double = 10.0,
    private val conditioner: SpeechConditioner? = SpeechConditioner(SAMPLE_RATE.toDouble()),
) : AudioWindowSource {
    companion object {
        const val SAMPLE_RATE = 16000

        /** The end of the quietest 30 ms in the search range. */
        fun quietestPoint(samples: FloatArray, count: Int, limit: Int, search: Double): Int {
            val frame = (0.03 * SAMPLE_RATE).toInt()
            val lowest = maxOf(limit - (search * SAMPLE_RATE).toInt(), frame)
            var best = limit
            var bestEnergy = Float.MAX_VALUE
            var index = lowest
            while (index + frame <= minOf(limit, count)) {
                var energy = 0f
                for (offset in index until index + frame) energy += samples[offset] * samples[offset]
                if (energy < bestEnergy) {
                    bestEnergy = energy
                    best = index + frame / 2
                }
                index += frame
            }
            return best
        }
    }

    override suspend fun duration(file: File): Double = withContext(Dispatchers.IO) { AudioDecoder(file, SAMPLE_RATE).use { it.duration } }

    override fun windows(file: File, from: Double): Flow<AudioWindow> = flow {
        AudioDecoder(file, SAMPLE_RATE, from).use { decoder ->
            val target = (windowDuration * SAMPLE_RATE).toInt()
            var pending = FloatArray(target + SAMPLE_RATE * 30)
            var count = 0
            var position = from
            var finished = false
            while (true) {
                while (count < target && !finished) {
                    val chunk = decoder.read()
                    if (chunk == null) {
                        finished = true
                    } else {
                        if (count + chunk.size > pending.size) pending = pending.copyOf(maxOf(pending.size * 2, count + chunk.size))
                        System.arraycopy(chunk, 0, pending, 0 + count, chunk.size)
                        count += chunk.size
                    }
                }
                if (count == 0) break
                val cut = if (finished && count <= target) count else quietestPoint(pending, count, minOf(target, count), searchDuration)
                val samples = pending.copyOf(cut)
                System.arraycopy(pending, cut, pending, 0, count - cut)
                count -= cut
                val start = position
                position += cut.toDouble() / SAMPLE_RATE
                emit(AudioWindow(start, position, conditioner?.process(samples) ?: samples))
            }
        }
    }.flowOn(Dispatchers.Default)
}
