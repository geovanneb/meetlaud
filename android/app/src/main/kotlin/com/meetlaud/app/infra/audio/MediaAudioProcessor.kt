package com.meetlaud.app.infra.audio

import com.meetlaud.app.infra.capture.SegmentFormat
import com.meetlaud.domain.AudioProcessor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

/**
 * Converts and joins finished files, on the device, with the system's codecs, as AssetAudioProcessor.swift. Every
 * result is the app's own format: AAC in M4A, mono, at the capture rate.
 */
class MediaAudioProcessor : AudioProcessor {
    override suspend fun importAudio(source: File, file: File): Double = write(listOf(source), file)

    override suspend fun merge(sources: List<File>, file: File): Double = write(sources, file)

    private suspend fun write(sources: List<File>, file: File): Double = withContext(Dispatchers.Default) {
        // A temporary name means that the final path only ever holds a complete file.
        val temporary = File(file.parentFile, "${UUID.randomUUID()}.m4a")
        try {
            val writer = AacWriter(temporary, SegmentFormat.SAMPLE_RATE)
            try {
                for (source in sources) {
                    AudioDecoder(source, SegmentFormat.SAMPLE_RATE).use { decoder ->
                        while (true) writer.write(decoder.read() ?: break)
                    }
                }
                writer.finish()
            } catch (error: Throwable) {
                writer.close()
                throw error
            }
            if (writer.frames == 0L) throw AudioUnavailableException("No audio")
            file.delete()
            if (!temporary.renameTo(file)) throw AudioUnavailableException("Cannot save")
            writer.frames.toDouble() / SegmentFormat.SAMPLE_RATE
        } finally {
            temporary.delete()
        }
    }
}
