package com.meetlaud.app.infra.engines

import com.meetlaud.domain.LanguageModelEngine
import com.meetlaud.domain.LanguageRequest
import com.meetlaud.domain.ModelDescriptor
import com.meetlaud.domain.ModelRole
import com.meetlaud.domain.TextEmbeddingEngine
import kotlinx.coroutines.flow.Flow
import java.io.File

/**
 * llama.cpp runs two kinds of model: one that writes and one that searches. The model manager asks for an engine
 * by runtime, so this one stands for both and sends each model to the right one by its role.
 */
class LlamaRunner(private val language: LlamaLanguageEngine, private val search: LlamaEmbeddingEngine) :
    LanguageModelEngine, TextEmbeddingEngine {
    override suspend fun prepare(model: ModelDescriptor, folder: File?) =
        if (ModelRole.SEARCH in model.roles) search.prepare(model, folder) else language.prepare(model, folder)

    override suspend fun unload() {
        language.unload()
        search.unload()
    }

    override fun generate(request: LanguageRequest): Flow<String> = language.generate(request)
    override suspend fun modelID(language: String?): String? = search.modelID(language)
    override suspend fun detectLanguage(text: String): String? = search.detectLanguage(text)
    override suspend fun embed(texts: List<String>, language: String?): List<List<Float>> = search.embed(texts, language)
}
