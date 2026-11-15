package com.meetlaud.app.infra.engines

import com.meetlaud.domain.AudioWindow
import com.meetlaud.domain.ModelDescriptor
import com.meetlaud.domain.SpeechSegment
import com.meetlaud.domain.TranscriptionEngine
import com.meetlaud.domain.TranscriptionError
import com.meetlaud.domain.TranscriptionException
import com.meetlaud.domain.WindowResult
import com.meetlaud.engines.whisper.SegmentSink
import com.meetlaud.engines.whisper.WhisperNative
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.abs

/** Runs Whisper on the CPU with whisper.cpp, from files already on the device. As WhisperKitEngine.swift. */
class WhisperCppEngine : TranscriptionEngine {
    private val lane = engineLane()
    private var handle = 0L
    private var loadedModelID: String? = null

    override suspend fun prepare(model: ModelDescriptor, folder: File?) = withContext(lane) {
        if (loadedModelID == model.id && handle != 0L) return@withContext
        unloadInside()
        val file = modelFile(folder, ".bin") ?: throw TranscriptionException(TranscriptionError.MISSING_MODEL_FILES)
        handle = WhisperNative.load(file.path)
        if (handle == 0L) throw TranscriptionException(TranscriptionError.ENGINE_FAILED)
        loadedModelID = model.id
    }

    override suspend fun transcribe(window: AudioWindow, language: String?, hints: List<String>, progress: (Double) -> Unit): WindowResult {
        val context = currentCoroutineContext()
        return withContext(lane) {
            if (handle == 0L) throw TranscriptionException(TranscriptionError.MODEL_NOT_INSTALLED)
            // Whisper invents words for audio with nothing in it, so a window with no signal never reaches it.
            if (isSilent(window.samples)) {
                progress(1.0)
                return@withContext WindowResult(emptyList(), null)
            }
            val segments = mutableListOf<SpeechSegment>()
            // The hints are not given as a prompt, as on iOS: spellings are fixed in the text by VocabularyCorrector,
            // so both apps write the same transcript for the same audio.
            val heard = WhisperNative.transcribe(handle, window.samples, language, engineThreads, object : SegmentSink {
                override fun onSegment(startMs: Long, endMs: Long, text: ByteArray) {
                    segments += SpeechSegment(window.start + startMs / 1000.0, window.start + endMs / 1000.0, String(text, Charsets.UTF_8))
                }
                override fun onProgress(percent: Int) = progress(percent / 100.0)
                override fun isCancelled(): Boolean = !context.isActive
            })
            if (!context.isActive) throw kotlinx.coroutines.CancellationException()
            // A failed run fails the window, so nothing is saved for it and it is tried again.
            heard ?: throw TranscriptionException(TranscriptionError.ENGINE_FAILED)
            progress(1.0)
            WindowResult(segments.filter { it.text.isNotBlank() }, heard.ifEmpty { null })
        }
    }

    override suspend fun unload() = withContext(lane) { unloadInside() }

    private fun unloadInside() {
        if (handle != 0L) WhisperNative.free(handle)
        handle = 0L
        loadedModelID = null
    }

    companion object {
        /** Nothing above -60 dBFS: only true silence is skipped, a quiet room still goes to the model. */
        fun isSilent(samples: FloatArray): Boolean = samples.none { abs(it) >= 0.001f }
    }
}
