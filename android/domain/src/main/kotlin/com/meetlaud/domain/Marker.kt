package com.meetlaud.domain

import java.util.UUID

enum class MarkerKind(val raw: String) {
    FLAG("flag"), NOTE("note"), PHOTO("photo");

    companion object {
        fun from(raw: String): MarkerKind? = entries.firstOrNull { it.raw == raw }
    }
}

/** A moment the user marked while recording. `time` is position in the audio, which excludes pauses. */
data class Marker(
    val id: UUID = UUID.randomUUID(),
    val recordingID: RecordingID,
    val time: TimeInterval,
    val kind: MarkerKind,
    val text: String? = null,
    /** File name inside the recording's attachments folder. */
    val attachment: String? = null,
)

enum class PauseReason(val raw: String) {
    USER("user"), INTERRUPTION("interruption");

    companion object {
        fun from(raw: String): PauseReason? = entries.firstOrNull { it.raw == raw }
    }
}

/** A gap in a recording, so the timeline can show that time passed here. */
data class PauseSpan(
    val recordingID: RecordingID,
    val position: TimeInterval,
    val duration: TimeInterval,
    val reason: PauseReason,
)
