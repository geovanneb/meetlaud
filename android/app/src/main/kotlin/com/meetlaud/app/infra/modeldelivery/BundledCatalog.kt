package com.meetlaud.app.infra.modeldelivery

import android.content.Context
import com.meetlaud.domain.ModelCatalog
import com.meetlaud.domain.ModelDescriptor
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** The list of models, shipped inside the app, made by Tools/generate-android-catalog. There is no server of ours to ask. */
class BundledCatalog(context: Context) : ModelCatalog {
    @Serializable
    private data class Catalog(val schema: Int = 1, val models: List<ModelDescriptor>)

    override val models: List<ModelDescriptor> =
        Json { ignoreUnknownKeys = true }.decodeFromString<Catalog>(context.assets.open("models.json").bufferedReader().readText()).models
}
