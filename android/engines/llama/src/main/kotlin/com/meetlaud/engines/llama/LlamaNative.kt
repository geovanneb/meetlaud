package com.meetlaud.engines.llama

/** Receives generated text as UTF-8 bytes. Returns false to stop. */
fun interface ByteSink {
    fun onBytes(bytes: ByteArray): Boolean
}

/**
 * The JNI bridge to llama.cpp, and nothing else. Every call blocks, so callers run it off the main thread, one at a
 * time per model. Handles are native pointers: free each one exactly once.
 */
object LlamaNative {
    init {
        System.loadLibrary("meetlaud_llama")
    }

    /** A loaded GGUF model, or 0 when the file cannot be read. */
    external fun load(path: String): Long
    external fun free(handle: Long)
    external fun countTokens(handle: Long, text: ByteArray): Int
    /** The number of tokens written, or a negative number when the run failed. */
    external fun generate(handle: Long, prompt: ByteArray, maxTokens: Int, temperature: Float, seed: Int, threads: Int, sink: ByteSink): Int
    /** One unit-length vector per text, or null when the model cannot embed. */
    external fun embed(handle: Long, texts: Array<ByteArray>, maxTokens: Int, threads: Int): Array<FloatArray>?
}
