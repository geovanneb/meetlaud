package com.meetlaud.app.infra.engines

import com.meetlaud.domain.ModelDescriptor
import com.meetlaud.domain.TextEmbeddingEngine
import com.meetlaud.domain.TranscriptionError
import com.meetlaud.domain.TranscriptionException
import com.meetlaud.engines.llama.LlamaNative
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Embeds text with a downloaded multilingual model, through llama.cpp. iOS uses the models built into the system;
 * Android has none, so this one is in the catalog. It covers every language of the app with one model, so a
 * Portuguese question also finds Japanese text.
 *
 * @param installed The search model on the device and its folder, or null when there is none yet.
 */
class LlamaEmbeddingEngine(private val installed: suspend () -> Pair<ModelDescriptor, File?>?) : TextEmbeddingEngine {
    private val lane = engineLane()
    private var handle = 0L
    private var loadedModelID: String? = null

    private companion object {
        /** Chunks stay well under this. Pasted text might not, and its middle is what gets dropped. */
        const val TOKEN_LIMIT = 512
    }

    override suspend fun prepare(model: ModelDescriptor, folder: File?) = withContext(lane) { load(model, folder) }

    private fun load(model: ModelDescriptor, folder: File?) {
        if (loadedModelID == model.id && handle != 0L) return
        unloadInside()
        val file = modelFile(folder, ".gguf") ?: throw TranscriptionException(TranscriptionError.MISSING_MODEL_FILES)
        handle = LlamaNative.load(file.path)
        if (handle == 0L) throw TranscriptionException(TranscriptionError.ENGINE_FAILED)
        loadedModelID = model.id
    }

    override suspend fun modelID(language: String?): String? = installed()?.first?.id

    override suspend fun detectLanguage(text: String): String? = LanguageGuess.of(text)

    override suspend fun embed(texts: List<String>, language: String?): List<List<Float>> {
        val (model, folder) = installed() ?: throw TranscriptionException(TranscriptionError.MODEL_NOT_INSTALLED)
        return withContext(lane) {
            load(model, folder)
            if (texts.isEmpty()) return@withContext emptyList()
            val vectors = LlamaNative.embed(handle, texts.map { it.toByteArray() }.toTypedArray(), TOKEN_LIMIT, engineThreads)
                ?: throw TranscriptionException(TranscriptionError.ENGINE_FAILED)
            vectors.map { it.toList() }
        }
    }

    override suspend fun unload() = withContext(lane) { unloadInside() }

    private fun unloadInside() {
        if (handle != 0L) LlamaNative.free(handle)
        handle = 0L
        loadedModelID = null
    }
}

/**
 * The language of a piece of text, among the app's four, as NLLanguageRecognizer constrained to them answers on
 * iOS. Japanese by its script; the others by their most common short words.
 */
object LanguageGuess {
    private val words = mapOf(
        "en" to setOf("the", "and", "is", "to", "of", "we", "that", "it", "for", "this", "with", "you", "are", "what"),
        "pt" to setOf("o", "a", "os", "as", "e", "é", "de", "do", "da", "que", "não", "um", "uma", "para", "com", "isso", "vamos", "você"),
        "es" to setOf("el", "la", "los", "las", "y", "es", "de", "del", "que", "no", "un", "una", "para", "con", "eso", "vamos", "usted", "qué"),
    )

    fun of(text: String): String? {
        if (text.isBlank()) return null
        val letters = text.count { it.isLetter() }
        val japanese = text.count { Character.UnicodeScript.of(it.code) in setOf(Character.UnicodeScript.HIRAGANA, Character.UnicodeScript.KATAKANA, Character.UnicodeScript.HAN) }
        if (letters > 0 && japanese * 3 >= letters) return "ja"
        val tokens = text.lowercase().split(Regex("[^\\p{L}]+")).filter { it.isNotEmpty() }
        val scores = words.mapValues { (_, set) -> tokens.count { it in set } }
        // Portuguese and Spanish share many words: the letters only one of them uses break the tie.
        val bonusPt = text.count { it in "ãõç" } + tokens.count { it in setOf("não", "você", "é") }
        val bonusEs = text.count { it in "ñ¿¡" } + tokens.count { it in setOf("qué", "usted", "el") }
        val adjusted = scores + mapOf("pt" to (scores["pt"] ?: 0) + bonusPt, "es" to (scores["es"] ?: 0) + bonusEs)
        val best = adjusted.maxByOrNull { it.value } ?: return null
        return if (best.value == 0) "en" else best.key
    }
}
