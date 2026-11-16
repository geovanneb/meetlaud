package com.meetlaud.app.infra.diarization

import com.meetlaud.domain.ModelDescriptor
import com.meetlaud.domain.ModelRuntime
import com.meetlaud.domain.SpeakerCount
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.sin

class DiarizationTest {
    @Test fun fftMatchesTheDefinition() {
        val n = 16
        val input = DoubleArray(n) { sin(2 * PI * 3 * it / n) + 0.5 * it }
        val real = input.copyOf()
        val imaginary = DoubleArray(n)
        Fft.transform(real, imaginary)
        for (k in 0 until n) {
            var re = 0.0
            var im = 0.0
            for (t in 0 until n) {
                re += input[t] * kotlin.math.cos(2 * PI * k * t / n)
                im -= input[t] * sin(2 * PI * k * t / n)
            }
            assertEquals(re, real[k], 1e-9)
            assertEquals(im, imaginary[k], 1e-9)
        }
    }

    @Test fun fbankHasOneRowPer10Milliseconds() {
        val second = FloatArray(16_000) { (0.1 * sin(2 * PI * 440 * it / 16_000)).toFloat() }
        val features = KaldiFbank.compute(second)
        assertEquals(1 + (16_000 - 400) / 160, features.size)
        // The mean over time is taken away.
        for (bin in 0 until KaldiFbank.BINS) assertEquals(0.0, features.sumOf { it[bin].toDouble() } / features.size, 1e-3)
    }

    @Test fun clusteringGroupsCloseVoicesAndKeepsCountWhenAsked() {
        fun voice(base: Int, noise: Int) = SpeakerClustering.normalized(FloatArray(8) { if (it == base) 1f else 0.05f * ((it + noise) % 3) })
        val voices = List(30) { voice(it % 3, it) }
        val labels = SpeakerClustering.cluster(voices)
        assertEquals(3, labels.toSet().size)
        voices.indices.forEach { assertEquals(labels[it % 3], labels[it]) }
        assertEquals(2, SpeakerClustering.cluster(voices, count = 2).toSet().size)
    }

    /**
     * The whole pipeline with the real models, on a fictional dialogue made with the computer's voices. Needs
     * DIARIZATION_MODELS (a folder with segmentation.onnx and embedding.onnx) and DIARIZATION_AUDIO (a 16 kHz mono
     * WAV with a truth.json next to it), so it is skipped in CI.
     */
    @Test fun separatesThreeVoices() = runBlocking {
        val models = System.getenv("DIARIZATION_MODELS")?.let(::File)
        val audio = System.getenv("DIARIZATION_AUDIO")?.let(::File)
        assumeTrue(models?.isDirectory == true && audio?.isFile == true)
        val engine = OnnxDiarizationEngine()
        engine.prepare(ModelDescriptor(id = "test", displayName = "Test", roles = emptyList(), runtime = ModelRuntime.ONNX, languages = emptyList()), models)
        val samples = readWav(audio!!)
        var offset = 0
        val turns = engine.diarize({
            if (offset >= samples.size) null else samples.copyOfRange(offset, minOf(samples.size, offset + 4096)).also { offset += it.size }
        }, SpeakerCount.Automatic)
        engine.unload()
        val truth = Regex("""\["(\w+)", ([\d.]+), ([\d.]+)]""").findAll(File(audio.parentFile, "truth.json").readText())
            .map { Triple(it.groupValues[1], it.groupValues[2].toDouble(), it.groupValues[3].toDouble()) }.toList()
        val assigned = truth.map { (voice, start, end) ->
            voice to turns.groupBy { it.speaker }.maxByOrNull { (_, list) -> list.sumOf { maxOf(0.0, minOf(it.end, end) - maxOf(it.start, start)) } }?.key
        }
        println("diarization: ${turns.map { it.speaker }.toSet().size} speakers, ${turns.groupBy { it.speaker }.mapValues { (_, list) -> list.sumOf { it.end - it.start }.toInt() }} seconds, $assigned")
        assertEquals(3, turns.map { it.speaker }.toSet().size)
        // Every line of one voice under one speaker, and no two voices under the same one.
        val byVoice = assigned.groupBy({ it.first }, { it.second })
        byVoice.values.forEach { assertEquals(it.toString(), 1, it.toSet().size) }
        assertEquals(3, byVoice.values.map { it.first() }.toSet().size)
        assertTrue(turns.all { it.embedding.size == 256 })
    }

    private fun readWav(file: File): FloatArray {
        val bytes = file.readBytes()
        // The data chunk follows the 44-byte header the converter writes.
        var position = 12
        while (position < bytes.size - 8) {
            val id = String(bytes, position, 4)
            val size = ByteBuffer.wrap(bytes, position + 4, 4).order(ByteOrder.LITTLE_ENDIAN).int
            if (id == "data") {
                val data = ByteBuffer.wrap(bytes, position + 8, size).order(ByteOrder.LITTLE_ENDIAN)
                return FloatArray(size / 2) { data.short / 32768f }
            }
            position += 8 + size
        }
        error("No data in ${file.name}")
    }

}
