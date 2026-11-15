package com.meetlaud.app.feature.shared

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.meetlaud.app.localization.L10n
import com.meetlaud.domain.JobProgress
import com.meetlaud.domain.ModelManager
import com.meetlaud.domain.ModelRole
import com.meetlaud.domain.RecordingID
import com.meetlaud.domain.SpeakerCount
import com.meetlaud.domain.SpeedEvidence
import com.meetlaud.domain.TimeInterval
import com.meetlaud.domain.TranscribePlan
import com.meetlaud.domain.TranscriptVersion
import com.meetlaud.domain.TranscriptionCoordinator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

enum class AutoTranscribe(val raw: String) {
    ASK("ask"), ALWAYS("always"), NEVER("never");

    val title: String
        get() = when (this) {
            ASK -> L10n.Transcript.autoAsk
            ALWAYS -> L10n.Transcript.autoAlways
            NEVER -> L10n.Transcript.autoNever
        }

    companion object {
        const val STORAGE_KEY = "transcription.auto"
        fun from(raw: String?): AutoTranscribe = entries.firstOrNull { it.raw == raw } ?: ASK
    }
}

enum class TranscribeOutcome {
    STARTED,
    /** No installed model can do this. The person needs to get one. */
    NEEDS_MODEL,
}

/** Shows and starts transcription work from any screen. There is one for the life of the app. */
class TranscriptionCenter(private val coordinator: TranscriptionCoordinator, private val manager: ModelManager, scope: CoroutineScope) {
    var progress by mutableStateOf<Map<RecordingID, JobProgress>>(emptyMap())
        private set

    init {
        scope.launch { coordinator.updates.collect { progress = it } }
    }

    suspend fun transcribe(id: RecordingID, language: String?, whenCharging: Boolean = false): TranscribeOutcome {
        val model = manager.model(ModelRole.TRANSCRIPTION, language) ?: return TranscribeOutcome.NEEDS_MODEL
        runCatching { coordinator.enqueue(id, model.id, language, whenCharging) }
        return TranscribeOutcome.STARTED
    }

    /** Null when no model can transcribe this, which the start itself reports. */
    suspend fun plan(duration: TimeInterval, language: String?): TranscribePlan? {
        val model = manager.model(ModelRole.TRANSCRIPTION, language) ?: return null
        val snapshot = manager.makeSnapshot()
        val speed = snapshot.fits[ModelRole.TRANSCRIPTION]?.firstOrNull { it.model.id == model.id }?.speed ?: SpeedEvidence.Unknown
        return TranscribePlan(duration, speed, snapshot.rightNow, snapshot.condition.isCharging)
    }

    suspend fun canSeparateSpeakers(): Boolean = coordinator.canSeparateSpeakers()

    /** Separates voices again, with the number of people the person knows spoke. */
    suspend fun redetectSpeakers(id: RecordingID, count: SpeakerCount) {
        runCatching { coordinator.redetectSpeakers(id, count) }
    }

    suspend fun cancel(id: RecordingID) {
        runCatching { coordinator.cancel(id) }
    }

    suspend fun restore(version: TranscriptVersion) {
        runCatching { coordinator.restore(version) }
    }
}
