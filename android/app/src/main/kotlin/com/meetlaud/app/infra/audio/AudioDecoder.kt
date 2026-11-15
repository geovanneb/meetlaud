package com.meetlaud.app.infra.audio

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.Closeable
import java.io.File
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.sin

class AudioUnavailableException(message: String) : Exception(message)

/**
 * Reads any audio or video file the system can decode, as mono samples at `targetRate`, a little at a time, so that
 * memory stays flat however long the file. The counterpart of AVAudioFile with an AVAudioConverter.
 */
class AudioDecoder(file: File, private val targetRate: Int, start: Double = 0.0) : Closeable {
    private val extractor = MediaExtractor()
    private val codec: MediaCodec
    private val info = MediaCodec.BufferInfo()
    private var inputDone = false
    private var outputDone = false
    private var sourceRate: Int
    private var channels: Int
    private var resampler: Resampler
    private val startUs = (start * 1_000_000).toLong()

    /** Seconds, from the container. */
    val duration: Double

    init {
        extractor.setDataSource(file.path)
        val track = (0 until extractor.trackCount).firstOrNull {
            extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
        } ?: run {
            extractor.release()
            throw AudioUnavailableException("No audio track")
        }
        extractor.selectTrack(track)
        val format = extractor.getTrackFormat(track)
        duration = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) / 1_000_000.0 else 0.0
        sourceRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        resampler = Resampler(sourceRate, targetRate)
        codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        codec.configure(format, null, null, 0)
        codec.start()
        if (startUs > 0) extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
    }

    /** The next samples at the target rate, or null at the end. A resampler holds back a little audio, which the end flushes. */
    fun read(): FloatArray? {
        while (!outputDone) {
            if (!inputDone) {
                val index = codec.dequeueInputBuffer(10_000)
                if (index >= 0) {
                    val buffer = codec.getInputBuffer(index)!!
                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0) {
                        codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            val out = codec.dequeueOutputBuffer(info, 10_000)
            if (out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                val format = codec.outputFormat
                val rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                if (rate != sourceRate) {
                    sourceRate = rate
                    resampler = Resampler(sourceRate, targetRate)
                }
                continue
            }
            if (out < 0) continue
            val buffer = codec.getOutputBuffer(out)!!
            val end = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
            var mono = FloatArray(0)
            if (info.size > 0) {
                buffer.position(info.offset)
                buffer.limit(info.offset + info.size)
                val shorts = buffer.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
                val frames = shorts.remaining() / channels
                mono = FloatArray(frames) { frame ->
                    var sum = 0f
                    for (channel in 0 until channels) sum += shorts.get(frame * channels + channel)
                    sum / channels / 32768f
                }
                // A seek lands on the frame before the start: what comes before it is dropped.
                if (startUs > 0 && info.presentationTimeUs < startUs) {
                    val skip = ((startUs - info.presentationTimeUs) * sourceRate / 1_000_000).toInt()
                    mono = if (skip >= mono.size) FloatArray(0) else mono.copyOfRange(skip, mono.size)
                }
            }
            codec.releaseOutputBuffer(out, false)
            if (end) outputDone = true
            val resampled = resampler.process(mono, flush = end)
            if (resampled.isNotEmpty()) return resampled
        }
        return null
    }

    override fun close() {
        runCatching { codec.stop() }
        codec.release()
        extractor.release()
    }
}

/**
 * Changes the sample rate with a windowed sinc, streaming. Below the source rate it filters first, so that nothing
 * above the new Nyquist folds back into speech as noise.
 */
class Resampler(private val from: Int, private val to: Int) {
    private val ratio = from.toDouble() / to
    private val cutoff = minOf(1.0, to.toDouble() / from)
    private val half = 16
    private var history = FloatArray(0)
    /** Position of the next output sample, in source samples, relative to the start of `history`. */
    private var position = half.toDouble()

    fun process(input: FloatArray, flush: Boolean = false): FloatArray {
        if (from == to) return input
        val padded = if (flush) input + FloatArray(half) else input
        val buffer = history + padded
        val output = ArrayList<Float>((padded.size / ratio).toInt() + 4)
        while (position + half < buffer.size) {
            output.add(sample(buffer, position))
            position += ratio
        }
        val keep = maxOf(0, floor(position).toInt() - half)
        history = buffer.copyOfRange(keep, buffer.size)
        position -= keep
        return output.toFloatArray()
    }

    private fun sample(buffer: FloatArray, at: Double): Float {
        val center = floor(at).toInt()
        var sum = 0.0
        var weight = 0.0
        for (index in center - half + 1..center + half) {
            if (index < 0 || index >= buffer.size) continue
            val x = (at - index) * cutoff
            val sinc = if (x == 0.0) 1.0 else sin(PI * x) / (PI * x)
            val window = 0.5 + 0.5 * cos(PI * (at - index) / half)
            val w = sinc * window
            sum += buffer[index] * w
            weight += w
        }
        return if (weight == 0.0) 0f else (sum / weight).toFloat()
    }
}
