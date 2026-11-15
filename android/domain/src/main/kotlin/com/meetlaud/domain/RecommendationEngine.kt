package com.meetlaud.domain

import java.time.Duration
import java.time.Instant

enum class FitLabel { UNSUPPORTED, NOT_RECOMMENDED, MAY_SLOW, GOOD, BEST }

sealed interface FitReason {
    data object BestForDevice : FitReason
    data object WorksWell : FitReason
    data object BelowTargetSpeed : FitReason
    data object NotEnoughMemory : FitReason
    data object UnstableHere : FitReason
    data class LanguageNotCovered(val language: String) : FitReason
}

sealed interface SpeedEvidence {
    /** Scaled from reference devices. Shown as a range. */
    data class Estimated(val low: Double, val high: Double) : SpeedEvidence
    /** Measured on this device. */
    data class Measured(val value: Double) : SpeedEvidence
    data object Unknown : SpeedEvidence

    /** A cautious single number for decisions. */
    val conservative: Double?
        get() = when (this) {
            is Estimated -> low
            is Measured -> value
            Unknown -> null
        }
}

data class ModelFit(val model: ModelDescriptor, val label: FitLabel, val reason: FitReason, val speed: SpeedEvidence) {
    val id: String get() = model.id
}

/** What a recommendation depends on, apart from the models themselves. */
data class RecommendationContext(
    val device: DeviceProfile,
    val languages: List<String>,
    val priority: Priority,
    val history: List<ModelRunStat>,
)

/** Decides which models suit this device. Pure and deterministic, so that a table of cases can prove it. */
class RecommendationEngine {
    companion object {
        /** Transcription slower than this feels broken: one hour would take 20 minutes. */
        const val MINIMUM_SPEED_X = 3.0
        /** Peak memory must fit this share of the device, because the system kills apps well before all of it. */
        const val MEMORY_BUDGET = 0.6
        /** Two kills mean that the model does not fit this device, whatever the numbers say. */
        const val KILLS_TO_MARK_UNSTABLE = 2
        /** Estimates are scaled across devices, so they carry this margin either way. */
        const val ESTIMATE_MARGIN = 0.3
    }

    fun recommend(role: ModelRole, catalog: List<ModelDescriptor>, context: RecommendationContext): List<ModelFit> {
        val fits = catalog
            .filter { it.roles.contains(role) }
            .map { assess(it, context) }
            .sortedWith { lhs, rhs ->
                if (lhs.label != rhs.label) rhs.label.compareTo(lhs.label)
                else score(rhs, context).compareTo(score(lhs, context))
            }
        val top = fits.firstOrNull() ?: return fits
        if (top.label != FitLabel.GOOD) return fits
        return listOf(ModelFit(top.model, FitLabel.BEST, FitReason.BestForDevice, top.speed)) + fits.drop(1)
    }

    /** Picks the installed model to use for a language in Automatic mode. */
    fun automaticModel(role: ModelRole, installed: List<ModelDescriptor>, language: String?, context: RecommendationContext): ModelDescriptor? {
        val scoped = context.copy(languages = language?.let { listOf(it) } ?: emptyList())
        return recommend(role, installed, scoped).firstOrNull { it.label >= FitLabel.MAY_SLOW }?.model
    }

    private fun assess(model: ModelDescriptor, context: RecommendationContext): ModelFit {
        val device = context.device
        val runs = context.history.filter { it.modelID == model.id }
        val speed = speedEvidence(model, device, runs)
        fun fit(label: FitLabel, reason: FitReason) = ModelFit(model, label, reason, speed)

        if (model.minMemoryMB.toDouble() > device.physicalMemoryMB.toDouble()) return fit(FitLabel.UNSUPPORTED, FitReason.NotEnoughMemory)
        context.languages.firstOrNull { !model.supports(it) }?.let { return fit(FitLabel.NOT_RECOMMENDED, FitReason.LanguageNotCovered(it)) }
        if (runs.count { it.outcome == ModelRunStat.Outcome.KILLED } >= KILLS_TO_MARK_UNSTABLE) return fit(FitLabel.NOT_RECOMMENDED, FitReason.UnstableHere)
        if (model.minMemoryMB.toDouble() > device.physicalMemoryMB * MEMORY_BUDGET) return fit(FitLabel.NOT_RECOMMENDED, FitReason.NotEnoughMemory)
        val value = speed.conservative
        if (value != null && value < MINIMUM_SPEED_X) return fit(FitLabel.MAY_SLOW, FitReason.BelowTargetSpeed)
        return fit(FitLabel.GOOD, FitReason.WorksWell)
    }

    private fun speedEvidence(model: ModelDescriptor, device: DeviceProfile, runs: List<ModelRunStat>): SpeedEvidence {
        runs.filter { it.outcome == ModelRunStat.Outcome.COMPLETED }.maxByOrNull { it.date }?.let { return SpeedEvidence.Measured(it.speedX) }
        val reference = model.reference.firstOrNull { it.device == device.identifier } ?: model.reference.firstOrNull()
            ?: return SpeedEvidence.Unknown
        // A probe compares this device with the reference one. Without it, the reference is the best guess.
        val scale = if (device.probeScore > 0 && reference.probeScore > 0) device.probeScore / reference.probeScore else 1.0
        val value = reference.speedX * scale
        return SpeedEvidence.Estimated(value * (1 - ESTIMATE_MARGIN), value * (1 + ESTIMATE_MARGIN))
    }

    private fun score(fit: ModelFit, context: RecommendationContext): Double {
        val codes = if (context.languages.isEmpty()) fit.model.quality.keys.toList() else context.languages
        val total = codes.mapNotNull { fit.model.quality[it] }.sum()
        val quality = if (codes.isEmpty()) 0.0 else total.toDouble() / codes.size
        val speed = minOf((fit.speed.conservative ?: MINIMUM_SPEED_X) / 10, 2.0)
        // Smaller wins ties, since a download costs the person something.
        val size = fit.model.totalBytes.toDouble() / 100_000_000_000
        return when (context.priority) {
            Priority.QUALITY -> quality * 3 + speed - size
            Priority.BALANCED -> quality * 2 + speed * 2 - size
            Priority.SPEED -> quality + speed * 3 - size
        }
    }
}

sealed interface RightNow {
    data object Great : RightNow
    data class Good(val reason: Reason) : RightNow
    data class Limited(val reason: Reason) : RightNow
    data object Paused : RightNow

    enum class Reason { WARM, HOT, LOW_POWER, LOW_BATTERY, LOW_MEMORY }

    /** Whether a heavy job should start, or wait for the device. */
    val allowsHeavyWork: Boolean get() = this != Paused

    companion object {
        fun evaluate(condition: DeviceCondition, requiredMemoryMB: Int = 0): RightNow = when {
            condition.thermal == ThermalLevel.CRITICAL -> Paused
            condition.thermal == ThermalLevel.SERIOUS -> Limited(Reason.HOT)
            condition.isLowPower -> Limited(Reason.LOW_POWER)
            requiredMemoryMB > 0 && condition.availableMemoryMB < requiredMemoryMB -> Limited(Reason.LOW_MEMORY)
            !condition.isCharging && condition.batteryLevel < 0.2 -> Limited(Reason.LOW_BATTERY)
            condition.thermal == ThermalLevel.FAIR -> Good(Reason.WARM)
            !condition.isCharging && condition.batteryLevel < 0.3 -> Good(Reason.LOW_BATTERY)
            else -> Great
        }
    }
}

sealed interface AdvisorSuggestion {
    data class BetterFit(val role: ModelRole, val modelID: String) : AdvisorSuggestion
    data class LanguageNotCovered(val language: String, val role: ModelRole) : AdvisorSuggestion
    data class Unstable(val modelID: String, val alternativeID: String?) : AdvisorSuggestion
    data class TooSlow(val modelID: String) : AdvisorSuggestion
    data class UnusedModel(val modelID: String, val bytes: Long) : AdvisorSuggestion

    val id: String
        get() = when (this) {
            is BetterFit -> "better-${role.raw}-$modelID"
            is LanguageNotCovered -> "language-$language-${role.raw}"
            is Unstable -> "unstable-$modelID"
            is TooSlow -> "slow-$modelID"
            is UnusedModel -> "unused-$modelID"
        }
}

/** Turns the device's situation into suggestions. It only ever suggests: nothing here changes anything. */
class AdvisorRules {
    companion object {
        val UNUSED_AFTER: Duration = Duration.ofDays(60)
        /** Below this, a model is worth flagging only if the disk is tight. */
        const val LOW_SPACE_BYTES = 2_000_000_000L
    }

    private val engine = RecommendationEngine()

    fun suggestions(
        catalog: List<ModelDescriptor>,
        installedIDs: Set<String>,
        context: RecommendationContext,
        condition: DeviceCondition,
        now: Instant,
    ): List<AdvisorSuggestion> {
        val result = mutableListOf<AdvisorSuggestion>()
        val installed = catalog.filter { it.id in installedIDs }

        for (role in ModelRole.entries) {
            val fits = engine.recommend(role, catalog, context)
            if (fits.isEmpty()) continue
            val language = context.languages.firstOrNull { code -> fits.none { it.model.supports(code) && it.model.id in installedIDs } }
            if (language != null && installed.any { it.roles.contains(role) }) {
                result.add(AdvisorSuggestion.LanguageNotCovered(language, role))
            }
            val usable = installed.filter { it.roles.contains(role) }
            val best = fits.firstOrNull { it.label == FitLabel.BEST }
            if (best != null && best.model.id !in installedIDs && usable.isNotEmpty()) {
                result.add(AdvisorSuggestion.BetterFit(role, best.model.id))
            }
        }

        for (model in installed) {
            val runs = context.history.filter { it.modelID == model.id }
            if (runs.count { it.outcome == ModelRunStat.Outcome.KILLED } >= RecommendationEngine.KILLS_TO_MARK_UNSTABLE) {
                val alternative = catalog.firstOrNull { it.id != model.id && it.minMemoryMB < model.minMemoryMB && it.roles.intersect(model.roles.toSet()).isNotEmpty() }
                result.add(AdvisorSuggestion.Unstable(model.id, alternative?.id))
            }
            val latest = runs.filter { it.outcome == ModelRunStat.Outcome.COMPLETED }.maxByOrNull { it.date }
            if (latest != null && latest.speedX < 1) result.add(AdvisorSuggestion.TooSlow(model.id))
            val lastUse = runs.maxOfOrNull { it.date }
            if (!model.isSystemManaged && condition.freeBytes < LOW_SPACE_BYTES &&
                (lastUse?.let { Duration.between(it, now) > UNUSED_AFTER } ?: true)
            ) {
                result.add(AdvisorSuggestion.UnusedModel(model.id, model.totalBytes))
            }
        }
        return result
    }
}
