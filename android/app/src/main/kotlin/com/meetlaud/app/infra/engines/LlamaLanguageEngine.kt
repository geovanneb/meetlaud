package com.meetlaud.app.infra.engines

import com.meetlaud.domain.LanguageModelEngine
import com.meetlaud.domain.LanguageRequest
import com.meetlaud.domain.ModelDescriptor
import com.meetlaud.domain.TranscriptionError
import com.meetlaud.domain.TranscriptionException
import com.meetlaud.engines.llama.LlamaNative
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.CodingErrorAction
import kotlin.random.Random

/** Runs a language model on the CPU with llama.cpp, from files already on the device. As MLXLanguageEngine.swift. */
class LlamaLanguageEngine : LanguageModelEngine {
    private val lane = engineLane()
    private var handle = 0L
    private var loadedModelID: String? = null

    override suspend fun prepare(model: ModelDescriptor, folder: File?) = withContext(lane) {
        if (loadedModelID == model.id && handle != 0L) return@withContext
        unloadInside()
        val file = modelFile(folder, ".gguf") ?: throw TranscriptionException(TranscriptionError.MISSING_MODEL_FILES)
        handle = LlamaNative.load(file.path)
        if (handle == 0L) throw TranscriptionException(TranscriptionError.ENGINE_FAILED)
        loadedModelID = model.id
    }

    override fun generate(request: LanguageRequest): Flow<String> = callbackFlow {
        val job = launch(lane) {
            if (handle == 0L) throw TranscriptionException(TranscriptionError.MODEL_NOT_INSTALLED)
            val decoder = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPLACE).onUnmappableCharacter(CodingErrorAction.REPLACE)
            var pending = ByteArray(0)
            val written = LlamaNative.generate(handle, ChatPrompt.chatML(request).toByteArray(), request.maxTokens, request.temperature, Random.nextInt(), engineThreads) { bytes ->
                // A character can be split across two tokens: only whole characters go out, the rest waits.
                val input = ByteBuffer.wrap(pending + bytes)
                val output = CharBuffer.allocate(input.remaining() + 1)
                decoder.decode(input, output, false)
                pending = ByteArray(input.remaining()).also { input.get(it) }
                output.flip()
                if (output.hasRemaining()) trySend(output.toString())
                isActive
            }
            if (written < 0) throw TranscriptionException(TranscriptionError.ENGINE_FAILED)
        }
        job.invokeOnCompletion { cause -> close(cause) }
        awaitClose { job.cancel() }
    }

    override suspend fun unload() = withContext(lane) { unloadInside() }

    private fun unloadInside() {
        if (handle != 0L) LlamaNative.free(handle)
        handle = 0L
        loadedModelID = null
    }
}

/** The prompt format of the Qwen models in the catalog, as their chat template writes it with thinking off. */
internal object ChatPrompt {
    fun chatML(request: LanguageRequest): String = buildString {
        if (request.system.isNotBlank()) append("<|im_start|>system\n").append(request.system.trim()).append("<|im_end|>\n")
        append("<|im_start|>user\n").append(request.prompt.trim()).append("<|im_end|>\n")
        append("<|im_start|>assistant\n<think>\n\n</think>\n\n")
    }
}
