package com.meetlaud.domain

import java.time.Instant
import java.util.UUID

/** Seconds, as a position or a length of audio. The counterpart of Foundation's TimeInterval. */
typealias TimeInterval = Double

/** Stable identity of a recording. A dedicated type prevents mixing it with other UUIDs. */
@JvmInline
value class RecordingID(val rawValue: UUID = UUID.randomUUID()) {
    override fun toString(): String = rawValue.toString().uppercase()

    companion object {
        /** Null for anything that is not a valid UUID, such as untrusted deep link input. */
        fun from(string: String): RecordingID? = parseUUID(string)?.let(::RecordingID)
    }
}

/** Accepts only the canonical 8-4-4-4-12 form, as Foundation's UUID(uuidString:) does. */
internal fun parseUUID(string: String): UUID? {
    if (!Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$").matches(string)) return null
    return runCatching { UUID.fromString(string) }.getOrNull()
}

enum class RecordingStatus(val raw: String) {
    /** Audio is being written, or the app died while writing it. Recovery looks for this state. */
    CAPTURING("capturing"),
    /** The final audio file exists. */
    READY("ready");

    companion object {
        fun from(raw: String): RecordingStatus? = entries.firstOrNull { it.raw == raw }
    }
}

/** The center of the product. Everything else in the domain relates to a recording. */
data class Recording(
    val id: RecordingID = RecordingID(),
    val title: String,
    val createdAt: Instant,
    /** Never negative: callers clamp, as the Swift initializer does. */
    val duration: TimeInterval = 0.0,
    val status: RecordingStatus = RecordingStatus.READY,
    /** True when the app rebuilt this recording after a crash. */
    val wasRecovered: Boolean = false,
    /** Null means the main Recordings list. */
    val folderID: FolderID? = null,
    /** When set, the recording is in the trash. */
    val deletedAt: Instant? = null,
    val attendees: List<String> = emptyList(),
)
