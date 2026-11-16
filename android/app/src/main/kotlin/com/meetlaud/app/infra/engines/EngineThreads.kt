package com.meetlaud.app.infra.engines

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import java.io.File

/** The threads a model may use. The big cores, at most four, so the phone stays cool for an hour-long meeting. */
internal val engineThreads: Int = (Runtime.getRuntime().availableProcessors() / 2).coerceIn(2, 4)

/** One native call at a time per engine, off the main thread, as an actor is on iOS. */
@OptIn(ExperimentalCoroutinesApi::class)
internal fun engineLane() = Dispatchers.IO.limitedParallelism(1)

/** The one model file in a folder, by extension. The catalog names it, but the folder is what is on disk. */
internal fun modelFile(folder: File?, extension: String): File? =
    folder?.walkTopDown()?.firstOrNull { it.isFile && it.name.endsWith(extension) }
