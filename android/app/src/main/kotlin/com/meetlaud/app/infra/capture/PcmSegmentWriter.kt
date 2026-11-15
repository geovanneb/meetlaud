package com.meetlaud.app.infra.capture

import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * The on-disk format of audio while it is being recorded, the same as iOS: raw 16-bit mono samples at 24 kHz, little
 * endian, with no header and no container. A process that dies mid-write leaves nothing to corrupt: the file size is
 * the length (D-028, SP-4).
 */
object SegmentFormat {
    const val SAMPLE_RATE = 24000
    const val BYTES_PER_FRAME = 2
    const val FILE_EXTENSION = "pcm"
}

/** Appends samples to numbered files. Not thread-safe: the caller serializes access. */
class PcmSegmentWriter(
    private val directory: File,
    segmentSeconds: Double = 60.0,
    /** Upper limit of audio lost on power failure. A process crash loses nothing. */
    syncSeconds: Double = 5.0,
) {
    private val framesPerSegment = (segmentSeconds * SegmentFormat.SAMPLE_RATE).toLong()
    private val framesPerSync = (syncSeconds * SegmentFormat.SAMPLE_RATE).toLong()
    private var stream: FileOutputStream? = null
    private var segmentIndex = 0
    private var framesInSegment = 0L
    private var framesSinceSync = 0L
    var framesWritten = 0L
        private set
    private val bytes = ByteBuffer.allocate(8192 * 2).order(ByteOrder.LITTLE_ENDIAN)

    fun append(samples: ShortArray, count: Int) {
        var offset = 0
        while (offset < count) {
            if (stream == null || framesInSegment >= framesPerSegment) rollOver()
            val take = minOf(count - offset, (framesPerSegment - framesInSegment).toInt(), 8192)
            bytes.clear()
            for (index in offset until offset + take) bytes.putShort(samples[index])
            stream!!.write(bytes.array(), 0, take * 2)
            framesInSegment += take
            framesSinceSync += take
            framesWritten += take
            offset += take
        }
        if (framesSinceSync >= framesPerSync) {
            stream?.fd?.sync()
            framesSinceSync = 0
        }
    }

    fun close() {
        stream?.let {
            it.flush()
            it.fd.sync()
            it.close()
        }
        stream = null
    }

    private fun rollOver() {
        close()
        segmentIndex += 1
        framesInSegment = 0
        stream = FileOutputStream(File(directory, name(segmentIndex)))
    }

    companion object {
        fun name(index: Int) = "part-%06d.%s".format(index, SegmentFormat.FILE_EXTENSION)
    }
}
