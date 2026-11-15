package com.meetlaud.app.infra.capture

import com.meetlaud.app.infra.audio.AacWriter
import com.meetlaud.domain.AudioAssembler
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID

class AssemblyException : Exception("noAudio")

/**
 * Encodes raw segments into the final M4A: AAC at 64 kbps mono, about 29 MB an hour, the same file iOS makes. Never
 * deletes the segments: the caller does, once the file is saved. The counterpart of AACAssembler.swift.
 */
class AacAssembler : AudioAssembler {
    companion object {
        const val BIT_RATE = 64000
        private const val CHUNK_FRAMES = 24000
    }

    override suspend fun assemble(segments: File, into: File): Double = withContext(Dispatchers.Default) {
        val parts = segments.listFiles { file -> file.extension == SegmentFormat.FILE_EXTENSION }?.sortedBy { it.name } ?: emptyList()
        // A temporary name means that the final path only ever holds a complete file.
        val temporary = File(into.parentFile, "${UUID.randomUUID()}.m4a")
        try {
            val writer = AacWriter(temporary, SegmentFormat.SAMPLE_RATE, BIT_RATE)
            try {
                val bytes = ByteArray(CHUNK_FRAMES * SegmentFormat.BYTES_PER_FRAME)
                val samples = ShortArray(CHUNK_FRAMES)
                for (part in parts) {
                    FileInputStream(part).use { input ->
                        while (true) {
                            val read = readFully(input, bytes)
                            // A crash can leave half a sample at the end of the file.
                            val count = read / SegmentFormat.BYTES_PER_FRAME
                            if (count <= 0) break
                            ByteBuffer.wrap(bytes, 0, count * 2).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(samples, 0, count)
                            writer.write(samples, count)
                        }
                    }
                }
                writer.finish()
            } catch (error: Throwable) {
                writer.close()
                throw error
            }
            if (writer.frames <= 0) throw AssemblyException()
            into.delete()
            if (!temporary.renameTo(into)) throw AssemblyException()
            writer.frames.toDouble() / SegmentFormat.SAMPLE_RATE
        } finally {
            temporary.delete()
        }
    }
}

/** As many bytes as fit, or fewer only at the end of the file. InputStream.readNBytes needs Android 13. */
private fun readFully(input: java.io.InputStream, bytes: ByteArray): Int {
    var total = 0
    while (total < bytes.size) {
        val read = input.read(bytes, total, bytes.size - total)
        if (read < 0) break
        total += read
    }
    return total
}
