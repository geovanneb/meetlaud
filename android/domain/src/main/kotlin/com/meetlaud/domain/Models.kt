package com.meetlaud.domain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant

@Serializable
enum class ModelRole {
    @SerialName("transcription") TRANSCRIPTION,
    @SerialName("speakerSeparation") SPEAKER_SEPARATION,
    @SerialName("voicePrint") VOICE_PRINT,
    @SerialName("chat") CHAT,
    @SerialName("search") SEARCH;

    val raw: String get() = when (this) {
        TRANSCRIPTION -> "transcription"
        SPEAKER_SEPARATION -> "speakerSeparation"
        VOICE_PRINT -> "voicePrint"
        CHAT -> "chat"
        SEARCH -> "search"
    }

    companion object {
        fun from(raw: String): ModelRole? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * The engine that runs a model. The first five are the iOS runtimes, kept so both catalogs share one schema. Android
 * runs whisper.cpp, llama.cpp, and ONNX Runtime (D-085).
 */
@Serializable
enum class ModelRuntime {
    @SerialName("appleSpeech") APPLE_SPEECH,
    @SerialName("appleLanguage") APPLE_LANGUAGE,
    @SerialName("whisperKit") WHISPER_KIT,
    @SerialName("fluidAudio") FLUID_AUDIO,
    @SerialName("mlx") MLX,
    @SerialName("whisperCpp") WHISPER_CPP,
    @SerialName("llamaCpp") LLAMA_CPP,
    @SerialName("onnx") ONNX,
}

@Serializable
data class ModelFile(
    /** Where the file goes inside the model's folder. */
    val path: String,
    val url: String,
    val size: Long,
    val sha256: String,
)

/** Speed measured by maintainers on a known device. Ships in the catalog. */
@Serializable
data class ReferenceSpeed(
    val device: String,
    /** Multiples of real time: 10 means an hour of audio takes 6 minutes. */
    val speedX: Double,
    val peakMemoryMB: Int,
    val probeScore: Double,
)

@Serializable
data class ModelDescriptor(
    val id: String,
    val version: String = "1",
    val displayName: String,
    val roles: List<ModelRole>,
    val runtime: ModelRuntime,
    val license: String = "MIT",
    val sourceHost: String = "huggingface.co",
    val repo: String = "",
    val files: List<ModelFile> = emptyList(),
    /** Language codes, such as "ja". */
    val languages: List<String>,
    val minMemoryMB: Int = 0,
    val backgroundCapable: Boolean = true,
    /** 1 to 5 per language, from our evaluation. Speed is measured on the device, quality is not. */
    val quality: Map<String, Int> = emptyMap(),
    val qualityIsProvisional: Boolean = false,
    val reference: List<ReferenceSpeed> = emptyList(),
) {
    val totalBytes: Long get() = files.sumOf { it.size }

    /** Models with no language list work on any voice. */
    fun supports(language: String): Boolean = languages.isEmpty() || languages.contains(language)

    /** Models the system installs and removes. Android has none: every model is a download. */
    val isSystemManaged: Boolean get() = runtime == ModelRuntime.APPLE_SPEECH || runtime == ModelRuntime.APPLE_LANGUAGE
}

enum class Priority(val raw: String) {
    SPEED("speed"), BALANCED("balanced"), QUALITY("quality");

    companion object {
        fun from(raw: String?): Priority? = entries.firstOrNull { it.raw == raw }
    }
}

sealed interface SelectionMode {
    data object Automatic : SelectionMode
    data class Pinned(val id: String) : SelectionMode
}

sealed interface InstallState {
    data object NotInstalled : InstallState
    data object Queued : InstallState
    data class Downloading(val received: Long, val total: Long) : InstallState
    data class Paused(val received: Long, val total: Long) : InstallState
    data object WaitingForWiFi : InstallState
    data object Verifying : InstallState
    data object Preparing : InstallState
    data object SelfTest : InstallState
    data object Ready : InstallState
    data class Failed(val failure: InstallFailure) : InstallState

    /** On its way: asked for, and neither ready nor given up on. */
    val isInFlight: Boolean
        get() = when (this) {
            Queued, is Downloading, is Paused, WaitingForWiFi, Verifying, Preparing, SelfTest -> true
            NotInstalled, Ready, is Failed -> false
        }
}

enum class InstallFailure(val raw: String) { NO_SPACE("noSpace"), DAMAGED("damaged"), UNAVAILABLE("unavailable"), PREPARE_FAILED("prepareFailed") }

enum class ThermalLevel { NOMINAL, FAIR, SERIOUS, CRITICAL }

/** What the device is, which rarely changes. */
data class DeviceProfile(
    val name: String,
    val identifier: String,
    val physicalMemoryMB: Int,
    val hasAppleIntelligence: Boolean = false,
    /** Result of the quick device probe. Zero until it has run. */
    val probeScore: Double = 0.0,
)

/** How the device is doing now, which changes minute by minute. */
data class DeviceCondition(
    val thermal: ThermalLevel = ThermalLevel.NOMINAL,
    val isLowPower: Boolean = false,
    val isCharging: Boolean = true,
    /** From 0 to 1. */
    val batteryLevel: Double = 1.0,
    val availableMemoryMB: Int = 4000,
    val freeBytes: Long = 50_000_000_000,
)

/** A speed test or a real job, on this device. */
data class ModelRunStat(
    val modelID: String,
    val audioDuration: TimeInterval,
    val wallTime: TimeInterval,
    val outcome: Outcome,
    val date: Instant,
) {
    enum class Outcome(val raw: String) { COMPLETED("completed"), KILLED("killed") }

    val speedX: Double get() = if (wallTime > 0) audioDuration / wallTime else 0.0
}
