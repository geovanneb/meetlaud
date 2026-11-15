package com.meetlaud.app.infra.audio

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.Closeable
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Writes 16-bit mono samples to an M4A file as AAC: the format of every finished recording, the same as iOS. Feed it
 * with `write` and end with `finish`.
 */
class AacWriter(output: File, private val sampleRate: Int, bitRate: Int = 64000) : Closeable {
    private val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
    private val muxer = MediaMuxer(output.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    private val info = MediaCodec.BufferInfo()
    private var track = -1
    private var finished = false
    var frames = 0L
        private set

    init {
        val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, 1).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
        }
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
    }

    fun write(samples: ShortArray, count: Int = samples.size) {
        var offset = 0
        while (offset < count) {
            val index = codec.dequeueInputBuffer(10_000)
            if (index >= 0) {
                val buffer = codec.getInputBuffer(index)!!
                buffer.clear()
                val take = minOf(count - offset, buffer.remaining() / 2)
                val bytes = ByteBuffer.allocate(take * 2).order(ByteOrder.LITTLE_ENDIAN)
                for (i in offset until offset + take) bytes.putShort(samples[i])
                buffer.put(bytes.array())
                codec.queueInputBuffer(index, 0, take * 2, frames * 1_000_000 / sampleRate, 0)
                frames += take
                offset += take
            }
            drain(false)
        }
    }

    fun write(samples: FloatArray) {
        write(ShortArray(samples.size) { (samples[it].coerceIn(-1f, 1f) * 32767).toInt().toShort() })
    }

    /** Ends the stream and closes the file. */
    fun finish() {
        if (finished) return
        finished = true
        while (true) {
            val index = codec.dequeueInputBuffer(10_000)
            if (index >= 0) {
                codec.queueInputBuffer(index, 0, 0, frames * 1_000_000 / sampleRate, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                break
            }
            drain(false)
        }
        drain(true)
        close()
    }

    private fun drain(untilEnd: Boolean) {
        while (true) {
            val out = codec.dequeueOutputBuffer(info, if (untilEnd) 10_000 else 0)
            when {
                out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    track = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                }
                out >= 0 -> {
                    val data = codec.getOutputBuffer(out)!!
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                    if (info.size > 0 && track >= 0) muxer.writeSampleData(track, data, info)
                    codec.releaseOutputBuffer(out, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
                !untilEnd -> return
            }
        }
    }

    override fun close() {
        runCatching { codec.stop() }
        codec.release()
        if (track >= 0) runCatching { muxer.stop() }
        runCatching { muxer.release() }
    }
}
