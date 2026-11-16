package com.meetlaud.app.infra.diarization

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import com.meetlaud.app.infra.audio.AudioDecoder
import com.meetlaud.domain.DiarizationEngine
import com.meetlaud.domain.ModelDescriptor
import com.meetlaud.domain.SpeakerCount
import com.meetlaud.domain.SpeakerTurn
import com.meetlaud.domain.TranscriptionError
import com.meetlaud.domain.TranscriptionException
import com.meetlaud.domain.VoiceSeparation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.FloatBuffer
import kotlin.math.ceil

/**
 * Tells who spoke when, on the device, as FluidDiarizationEngine.swift does on iOS. pyannote's segmentation model
 * finds up to three voices in each 10-second window, WeSpeaker gives each a voice print, and SpeakerClustering
 * groups the prints into people. Both models run with ONNX Runtime, which never opens a connection.
 *
 * The file is read by streaming, so memory stays flat however long the meeting is: a window of audio at a time,
 * and a few bytes per frame for the rest.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class OnnxDiarizationEngine : DiarizationEngine {
    private companion object {
        const val SAMPLE_RATE = 16_000
        const val WINDOW = 10 * SAMPLE_RATE
        /**
         * Five seconds between windows: every moment is heard by two of them. A step of two gave the same people on
         * a real recording and a synthetic one, at 2.3 times the cost, and took 16 minutes for 10 on a Snapdragon 680.
         */
        const val STEP = 5 * SAMPLE_RATE
        /** About half a second of one voice, the least a print can be trusted on. */
        const val MINIMUM_FRAMES = 30
        /** Frame i of the segmentation covers these many samples, as pyannote lays its 589 frames over the window. */
        val SAMPLES_PER_FRAME = ceil(WINDOW.toDouble() / WindowActivity.FRAMES).toInt()
        /** The classes of the segmentation model: who among three local speakers is talking. */
        val POWERSET = arrayOf(intArrayOf(), intArrayOf(0), intArrayOf(1), intArrayOf(2), intArrayOf(0, 1), intArrayOf(0, 2), intArrayOf(1, 2))
    }

    private val lane = Dispatchers.IO.limitedParallelism(1)
    private val environment = OrtEnvironment.getEnvironment()
    private var segmentation: OrtSession? = null
    private var embedding: OrtSession? = null

    override suspend fun prepare(model: ModelDescriptor, folder: File?) = withContext(lane) {
        if (segmentation != null) return@withContext
        val segmentationFile = folder?.let { File(it, "segmentation.onnx") }?.takeIf { it.exists() }
        val embeddingFile = folder?.let { File(it, "embedding.onnx") }?.takeIf { it.exists() }
        if (segmentationFile == null || embeddingFile == null) throw TranscriptionException(TranscriptionError.MISSING_MODEL_FILES)
        val options = OrtSession.SessionOptions().apply {
            setIntraOpNumThreads(com.meetlaud.app.infra.engines.engineThreads)
            setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
            // ONNX Runtime picks SME kernels when the CPU reports SME. Some report it without running it (the
            // emulator on Apple silicon crashed with an illegal instruction), and these two small models gain little.
            addConfigEntry("mlas.disable_kleidiai", "1")
        }
        segmentation = environment.createSession(segmentationFile.path, options)
        embedding = environment.createSession(embeddingFile.path, options)
    }

    override suspend fun unload() = withContext(lane) {
        segmentation?.close()
        embedding?.close()
        segmentation = null
        embedding = null
    }

    override suspend fun diarize(file: File, speakers: SpeakerCount): List<SpeakerTurn> = withContext(lane) {
        AudioDecoder(file, SAMPLE_RATE).use { decoder -> diarize(decoder::read, speakers) }
    }

    /** The pipeline itself, over 16 kHz mono samples in pieces of any size. `read` returns null at the end. */
    internal suspend fun diarize(read: () -> FloatArray?, speakers: SpeakerCount): List<SpeakerTurn> {
        val segmentation = segmentation ?: throw TranscriptionException(TranscriptionError.MODEL_NOT_INSTALLED)
        val embedding = embedding ?: throw TranscriptionException(TranscriptionError.MODEL_NOT_INSTALLED)
        val windows = mutableListOf<WindowActivity>()
        val voices = mutableListOf<LocalVoice>()
        var totalSamples = 0L
        // A window of audio, moved on by STEP each time.
        val buffer = FloatArray(WINDOW)
        var filled = 0
        var start = 0L
        var finished = false
        var pending = FloatArray(0)
        var pendingOffset = 0
        fun fill() {
            while (filled < WINDOW && !finished) {
                if (pendingOffset >= pending.size) {
                    val next = read()
                    if (next == null) {
                        finished = true
                        return
                    }
                    pending = next
                    pendingOffset = 0
                    continue
                }
                val take = minOf(WINDOW - filled, pending.size - pendingOffset)
                System.arraycopy(pending, pendingOffset, buffer, filled, take)
                filled += take
                pendingOffset += take
                totalSamples += take
            }
        }
        fill()
        while (filled > 0) {
            currentCoroutineContext().ensureActive()
            if (filled < WINDOW) buffer.fill(0f, filled, WINDOW)
            val activity = segment(segmentation, buffer)
            windows += WindowActivity(start, activity)
            voices += prints(embedding, buffer, filled, activity, windows.lastIndex)
            // The file has ended and all of what is left was in this window.
            if (finished) break
            System.arraycopy(buffer, STEP, buffer, 0, WINDOW - STEP)
            filled -= STEP
            start += STEP
            fill()
        }
        fun turns(count: Int?): List<SpeakerTurn> {
            val labels = SpeakerClustering.cluster(voices.map { it.vector }, count)
            val clusters = (labels.maxOrNull() ?: -1) + 1
            val byKey = voices.indices.associate { SpeakerClustering.key(voices[it].window, voices[it].speaker) to labels[it] }
            val centers = (0 until clusters).map { cluster ->
                val sum = FloatArray(voices.firstOrNull()?.vector?.size ?: 0)
                voices.indices.filter { labels[it] == cluster }.forEach { index -> voices[index].vector.forEachIndexed { k, value -> sum[k] += value } }
                SpeakerClustering.normalized(sum).toList()
            }
            return SpeakerClustering.reconstruct(windows, byKey, clusters, WINDOW, SAMPLE_RATE, totalSamples).map {
                SpeakerTurn("S${it.cluster}", it.start, it.end, centers[it.cluster])
            }
        }
        val found = when (speakers) {
            is SpeakerCount.Exactly -> return turns(speakers.count)
            SpeakerCount.Automatic -> turns(null)
        }
        // As on iOS: the automatic count can merge people whose voices are plainly apart (SP-3). One more speaker at
        // a time, keeping the largest count whose voices all stay clearly different.
        var best = found
        var count = found.map { it.speaker }.toSet().size
        while (count in 1 until VoiceSeparation.MOST_SPEAKERS && count < voices.size) {
            val candidate = turns(count + 1)
            if (candidate.map { it.speaker }.toSet().size != count + 1 || !VoiceSeparation.areDistinct(candidate)) break
            best = candidate
            count += 1
        }
        return best
    }

    /** The voices in one window, by frame. */
    private fun segment(session: OrtSession, window: FloatArray): ByteArray {
        val activity = ByteArray(WindowActivity.FRAMES * WindowActivity.LOCAL_SPEAKERS)
        OnnxTensor.createTensor(environment, FloatBuffer.wrap(window), longArrayOf(1, 1, WINDOW.toLong())).use { input ->
            session.run(mapOf("input_values" to input)).use { output ->
                @Suppress("UNCHECKED_CAST")
                val logits = (output[0].value as Array<Array<FloatArray>>)[0]
                for (frame in 0 until minOf(WindowActivity.FRAMES, logits.size)) {
                    val classes = logits[frame]
                    var best = 0
                    for (k in 1 until classes.size) if (classes[k] > classes[best]) best = k
                    for (speaker in POWERSET[best]) activity[frame * WindowActivity.LOCAL_SPEAKERS + speaker] = 1
                }
            }
        }
        return activity
    }

    /** A print for each voice with enough speech, from the frames where it talks alone when there are enough. */
    private fun prints(session: OrtSession, window: FloatArray, valid: Int, activity: ByteArray, index: Int): List<LocalVoice> {
        val result = mutableListOf<LocalVoice>()
        for (speaker in 0 until WindowActivity.LOCAL_SPEAKERS) {
            fun active(frame: Int) = activity[frame * WindowActivity.LOCAL_SPEAKERS + speaker].toInt() != 0
            fun alone(frame: Int): Boolean {
                if (!active(frame)) return false
                var others = 0
                for (k in 0 until WindowActivity.LOCAL_SPEAKERS) others += activity[frame * WindowActivity.LOCAL_SPEAKERS + k]
                return others == 1
            }
            val aloneFrames = (0 until WindowActivity.FRAMES).count(::alone)
            val useAlone = aloneFrames > MINIMUM_FRAMES
            if (!useAlone && (0 until WindowActivity.FRAMES).count(::active) < MINIMUM_FRAMES) continue
            val voiced = FloatArray(valid)
            var count = 0
            for (sample in 0 until valid) {
                val frame = sample / SAMPLES_PER_FRAME
                if (frame < WindowActivity.FRAMES && (if (useAlone) alone(frame) else active(frame))) voiced[count++] = window[sample]
            }
            val features = KaldiFbank.compute(voiced, count)
            if (features.size < 50) continue
            val flat = FloatArray(features.size * KaldiFbank.BINS)
            features.forEachIndexed { row, values -> System.arraycopy(values, 0, flat, row * KaldiFbank.BINS, KaldiFbank.BINS) }
            OnnxTensor.createTensor(environment, FloatBuffer.wrap(flat), longArrayOf(1, features.size.toLong(), KaldiFbank.BINS.toLong())).use { input ->
                session.run(mapOf("input_features" to input)).use { output ->
                    @Suppress("UNCHECKED_CAST")
                    val vector = (output[0].value as Array<FloatArray>)[0]
                    result += LocalVoice(index, speaker, SpeakerClustering.normalized(vector))
                }
            }
        }
        return result
    }
}
