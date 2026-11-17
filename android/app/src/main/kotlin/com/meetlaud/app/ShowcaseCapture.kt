package com.meetlaud.app

import com.meetlaud.domain.AudioCaptureEngine
import com.meetlaud.domain.AudioInput
import com.meetlaud.domain.CaptureEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import kotlin.math.abs
import kotlin.math.sin

/**
 * Time and a speech-like level, with no microphone: an emulator often has none that works. The counterpart of the
 * scripted engine iOS screenshots use (`--fake-capture`). Showcase only, so it never records anything.
 */
class ShowcaseCaptureEngine : AudioCaptureEngine {
    private val flow = MutableSharedFlow<CaptureEvent>(extraBufferCapacity = 64, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    override val events: Flow<CaptureEvent> = flow
    private val scope = CoroutineScope(Dispatchers.Default)
    private var clock: Job? = null
    private var recorded = 0.0

    override suspend fun start(directory: File) = resume()

    override suspend fun pause() {
        clock?.cancel()
    }

    override suspend fun resume() {
        clock?.cancel()
        clock = scope.launch {
            while (isActive) {
                delay(100)
                recorded += 0.1
                // Syllables inside words inside phrases, so the meter looks like someone talking.
                val level = 0.15 + 0.6 * abs(sin(recorded * 9.0)) * (0.55 + 0.45 * sin(recorded * 1.7)) * (0.7 + 0.3 * sin(recorded * 0.45))
                flow.emit(CaptureEvent.Progress(recorded, level.toFloat().coerceIn(0.05f, 1f)))
            }
        }
    }

    override suspend fun stop() {
        clock?.cancel()
    }

    override suspend fun deactivate() = Unit

    override suspend fun availableInputs(): List<AudioInput> = emptyList()

    override suspend fun selectInput(input: AudioInput) = Unit
}
