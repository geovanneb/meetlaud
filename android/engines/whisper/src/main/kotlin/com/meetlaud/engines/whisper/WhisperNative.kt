package com.meetlaud.engines.whisper

/** Receives a run's segments and progress. Called on the thread that runs the transcription. */
interface SegmentSink {
    /** Start and end in milliseconds from the start of the samples, and the text as UTF-8. */
    fun onSegment(startMs: Long, endMs: Long, text: ByteArray)
    /** From 0 to 100. */
    fun onProgress(percent: Int)
    /** Asked often during a run: true stops it. */
    fun isCancelled(): Boolean
}

/**
 * The JNI bridge to whisper.cpp, and nothing else. Every call blocks, so callers run it off the main thread, one at a
 * time per model. Handles are native pointers: free each one exactly once.
 */
object WhisperNative {
    init {
        System.loadLibrary("meetlaud_whisper")
    }

    /** A loaded ggml model, or 0 when the file cannot be read. */
    external fun load(path: String): Long
    external fun free(handle: Long)
    /** 16 kHz mono samples. The language it heard, or null when the run failed or was cancelled. */
    external fun transcribe(handle: Long, samples: FloatArray, language: String?, threads: Int, sink: SegmentSink): String?
}
