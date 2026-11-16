package com.meetlaud.domain

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Duration
import java.time.Instant
import java.util.Locale

/** Models that the system installs, requested by language. Android has none, so it passes an empty one. */
interface SystemSpeechAssets {
    suspend fun isInstalled(language: String): Boolean
    suspend fun install(language: String)
}

/** Everything the AI models screens show. */
data class ModelsSnapshot(
    val device: DeviceProfile,
    val condition: DeviceCondition,
    val rightNow: RightNow,
    val fits: Map<ModelRole, List<ModelFit>>,
    val states: Map<String, InstallState>,
    val selections: Map<ModelRole, SelectionMode>,
    val suggestions: List<AdvisorSuggestion>,
    val priority: Priority,
) {
    fun state(id: String): InstallState = states[id] ?: InstallState.NotInstalled

    fun isInstalled(id: String): Boolean = state(id) == InstallState.Ready

    /** The models that make up the one-tap setup: the best fit for each role with models available. */
    val recommendedSetup: List<ModelDescriptor>
        get() {
            val seen = HashSet<String>()
            return ModelRole.entries.mapNotNull { role -> fits[role]?.firstOrNull { it.label >= FitLabel.GOOD }?.model }
                .filter { seen.add(it.id) }
        }

    val missingFromSetup: List<ModelDescriptor>
        get() = recommendedSetup.filter { !isInstalled(it.id) && !it.isSystemManaged }

    /**
     * The one-tap setup as one figure, while any part of it is on its way. Null otherwise. Installed models count as
     * received, so the figure never goes back when one of them finishes.
     */
    val setupProgress: SetupProgress?
        get() {
            val models = recommendedSetup.filter { !it.isSystemManaged }
            val states = models.map { state(it.id) }
            if (states.none { it.isInFlight }) return null
            var received = 0L
            var total = 0L
            models.zip(states).forEach { (model, state) ->
                when (state) {
                    InstallState.NotInstalled, is InstallState.Failed -> return@forEach
                    InstallState.Queued, InstallState.WaitingForWiFi -> {}
                    is InstallState.Downloading -> received += minOf(state.received, model.totalBytes)
                    is InstallState.Paused -> received += minOf(state.received, model.totalBytes)
                    InstallState.Verifying, InstallState.Preparing, InstallState.SelfTest, InstallState.Ready -> received += model.totalBytes
                }
                total += model.totalBytes
            }
            return SetupProgress(received, total, SetupProgress.Phase.of(states))
        }
}

/** How far the one-tap setup has come. */
data class SetupProgress(val received: Long, val total: Long, val phase: Phase) {
    enum class Phase {
        /** At least one file is moving, or about to. */
        DOWNLOADING,
        /** Nothing moves until Wi-Fi is back. */
        WAITING_FOR_WIFI,
        /** Nothing moves until the person resumes. */
        PAUSED,
        /** Every file is here. What remains is checking and preparing. */
        FINISHING;

        companion object {
            fun of(states: List<InstallState>): Phase = when {
                states.any { it is InstallState.Downloading || it == InstallState.Queued } -> DOWNLOADING
                states.any { it == InstallState.WaitingForWiFi } -> WAITING_FOR_WIFI
                states.any { it is InstallState.Paused } -> PAUSED
                else -> FINISHING
            }
        }
    }

    val fraction: Double get() = if (total > 0) minOf(received.toDouble() / total, 1.0) else 0.0
}

/** What one model made of the same audio. */
data class ModelTrial(val modelID: String, val text: String, val seconds: TimeInterval) {
    val id: String get() = modelID
}

/** Connects the catalog, the installer, and the device, and keeps one current recommendation. */
class ModelManager(
    internal val catalog: ModelCatalog,
    internal val installer: ModelInstaller,
    private val usage: ModelUsageStore,
    private val device: DeviceMonitor,
    private val assets: SystemSpeechAssets,
    private val languageAssets: SystemSpeechAssets? = null,
    internal val arbiter: ModelArbiter,
    private val defaults: Preferences,
    internal val engines: (ModelRuntime) -> ModelRunner?,
    internal val now: () -> Instant = { Instant.now() },
    /** The person's languages, as two-letter codes, most preferred first. */
    private val preferredLanguages: () -> List<String> = { listOf(Locale.getDefault().language) },
) {
    private val engine = RecommendationEngine()
    private val rules = AdvisorRules()
    private val lane = actorLane()
    private val scope = CoroutineScope(SupervisorJob() + lane)

    private var hasAskedForSearchModel = false
    private var profile: DeviceProfile? = null
    private val overrides = HashMap<String, InstallState>()
    private val dismissed: MutableSet<String> = (defaults.stringList(DISMISSED_KEY) ?: emptyList()).toMutableSet()
    private val tasks = mutableListOf<Job>()

    private val snapshotFlow = MutableStateFlow<ModelsSnapshot?>(null)
    val snapshots: StateFlow<ModelsSnapshot?> = snapshotFlow.asStateFlow()

    companion object {
        private const val DISMISSED_KEY = "models.dismissedSuggestions"
        private const val PRIORITY_KEY = "models.priority"
        private const val LANGUAGES_KEY = "models.languages"
        private val supported = listOf("en", "ja", "pt", "es")
    }

    private suspend fun <T> isolated(block: suspend () -> T): T = withContext(lane) { block() }

    /** Starts watching. Everything after this is event driven. */
    suspend fun start() = isolated {
        installer.reconnect()
        publish()
        tasks.add(scope.launch { installer.events.collect { (id, state) -> handle(id, state) } })
        tasks.add(scope.launch { device.changes.collect { publish() } })
    }

    val priority: Priority get() = Priority.from(defaults.string(PRIORITY_KEY)) ?: Priority.BALANCED

    suspend fun setPriority(priority: Priority) = isolated {
        defaults.setString(PRIORITY_KEY, priority.raw)
        publish()
    }

    val languages: List<String> get() = defaults.stringList(LANGUAGES_KEY) ?: deviceLanguages()

    suspend fun setLanguages(languages: List<String>) = isolated {
        defaults.setStringList(LANGUAGES_KEY, languages)
        publish()
    }

    private fun deviceLanguages(): List<String> {
        val matches = preferredLanguages().filter { it in supported }
        return if (matches.isEmpty()) listOf("en") else matches.toSet().sorted()
    }

    // MARK: - Actions

    suspend fun install(model: ModelDescriptor, allowsCellular: Boolean = false) = isolated {
        if (model.isSystemManaged) installSystemAssets(model) else installer.install(model, allowsCellular)
    }

    /** Search is better with these, and they come from the system. Once per launch. */
    suspend fun installSearchModelIfNeeded() = isolated {
        if (hasAskedForSearchModel) return@isolated
        hasAskedForSearchModel = true
        for (model in catalog.models) {
            if (ModelRole.SEARCH in model.roles && model.isSystemManaged && systemOrInstallerState(model) != InstallState.Ready) {
                installSystemAssets(model)
            }
        }
    }

    /** Part of erasing everything. */
    suspend fun removeAllModels() = isolated {
        for (id in installer.installedIDs()) runCatching { installer.remove(id) }
        publish()
    }

    suspend fun installRecommended(allowsCellular: Boolean = false) = isolated {
        val snapshot = makeSnapshot()
        // The smallest first, so that the app becomes useful as soon as possible. A model already on its way is left
        // alone: asking again would restart a check or a preparation.
        val missing = snapshot.missingFromSetup.filter { !snapshot.state(it.id).isInFlight }
        for (model in missing.sortedBy { it.totalBytes }) {
            if (model.isSystemManaged) installSystemAssets(model) else installer.install(model, allowsCellular)
        }
    }

    /** Resumes the paused part of the setup, and nothing else: not what the person cancelled, not what failed. */
    suspend fun resumeSetup(allowsCellular: Boolean = false) = isolated {
        val snapshot = makeSnapshot()
        for (model in snapshot.missingFromSetup) {
            if (snapshot.state(model.id) is InstallState.Paused) installer.install(model, allowsCellular)
        }
    }

    suspend fun pause(id: String) = installer.pause(id)

    suspend fun cancel(id: String) = installer.cancel(id)

    suspend fun remove(id: String) = isolated {
        installer.remove(id)
        overrides.remove(id)
        for (role in ModelRole.entries) {
            if (usage.selection(role) == SelectionMode.Pinned(id)) usage.setSelection(SelectionMode.Automatic, role)
        }
        publish()
    }

    suspend fun select(mode: SelectionMode, role: ModelRole) = isolated {
        usage.setSelection(mode, role)
        publish()
    }

    suspend fun dismiss(suggestion: AdvisorSuggestion) = isolated {
        dismissed.add(suggestion.id)
        defaults.setStringList(DISMISSED_KEY, dismissed.toList())
        publish()
    }

    /** Times one pass of a clip, and records it. Speed is what the device can tell us. Quality is not. */
    suspend fun runSpeedTest(modelID: String, clip: AudioWindow, passes: Int): ModelRunStat {
        val model = catalog.models.firstOrNull { it.id == modelID }
        val runner = model?.let { engines(it.runtime) } as? TranscriptionEngine
            ?: throw TranscriptionException(TranscriptionError.MODEL_NOT_INSTALLED)
        // A test is optional, so it gives way to real work instead of waiting for it.
        if (!arbiter.tryAcquire()) throw ModelBusyException()
        val started: Instant
        try {
            runner.prepare(model, installer.folder(modelID))
            started = now()
            repeat(maxOf(passes, 1)) {
                currentCoroutineContext().ensureActive()
                runner.transcribe(clip, languages.firstOrNull())
            }
        } finally {
            withContext(NonCancellable) {
                runner.unload()
                arbiter.release()
            }
        }
        val stat = ModelRunStat(
            modelID, (clip.end - clip.start) * maxOf(passes, 1), seconds(started, now()), ModelRunStat.Outcome.COMPLETED, now(),
        )
        usage.insert(stat)
        isolated { publish() }
        return stat
    }

    /** The same audio through each model, one at a time, so that a person can judge what no benchmark measures. */
    suspend fun tryModels(ids: List<String>, clip: AudioWindow): List<ModelTrial> {
        // Optional work gives way to real work, as a speed test does.
        if (!arbiter.tryAcquire()) throw ModelBusyException()
        try {
            return ids.map {
                currentCoroutineContext().ensureActive()
                trial(it, clip)
            }
        } finally {
            withContext(NonCancellable) { arbiter.release() }
        }
    }

    private suspend fun trial(id: String, clip: AudioWindow): ModelTrial {
        val model = catalog.models.firstOrNull { it.id == id }
        val runner = model?.let { engines(it.runtime) } as? TranscriptionEngine
            ?: throw TranscriptionException(TranscriptionError.MODEL_NOT_INSTALLED)
        try {
            runner.prepare(model, installer.folder(id))
            val started = now()
            val result = runner.transcribe(clip, null)
            return ModelTrial(id, result.segments.joinToString(" ") { it.text }, seconds(started, now()))
        } finally {
            withContext(NonCancellable) { runner.unload() }
        }
    }

    /** Times a fixed batch of text, about what one meeting turns into. */
    suspend fun runSearchTest(modelID: String): SearchSpeed {
        val model = catalog.models.firstOrNull { it.id == modelID }
        val runner = model?.let { engines(it.runtime) } as? TextEmbeddingEngine
            ?: throw TranscriptionException(TranscriptionError.MODEL_NOT_INSTALLED)
        if (!arbiter.tryAcquire()) throw ModelBusyException()
        val batch = List(48) { SearchSpeed.SAMPLE }
        try {
            val started = now()
            runner.embed(batch, "en")
            val elapsed = seconds(started, now())
            return SearchSpeed(modelID, batch.size / maxOf(elapsed, 0.001))
        } finally {
            withContext(NonCancellable) {
                runner.unload()
                arbiter.release()
            }
        }
    }

    /** Times a short answer. Foreground only, like every use of a language model. */
    suspend fun runLanguageTest(modelID: String): LanguageSpeed {
        val model = catalog.models.firstOrNull { it.id == modelID }
        val runner = model?.let { engines(it.runtime) } as? LanguageModelEngine
            ?: throw TranscriptionException(TranscriptionError.MODEL_NOT_INSTALLED)
        if (!arbiter.tryAcquire()) throw ModelBusyException()
        try {
            runner.prepare(model, installer.folder(modelID))
            val request = LanguageRequest(
                system = "You write clear notes.",
                prompt = "Explain in a few sentences why meetings should end with clear next steps.",
                maxTokens = 120,
            )
            val started = now()
            var first: Instant? = null
            var chunks = 0
            runner.generate(request).collect {
                first = first ?: now()
                chunks += 1
            }
            currentCoroutineContext().ensureActive()
            val writing = seconds(first ?: started, now())
            return LanguageSpeed(modelID, chunks / maxOf(writing, 0.001), seconds(started, first ?: started))
        } finally {
            withContext(NonCancellable) {
                runner.unload()
                arbiter.release()
            }
        }
    }

    // MARK: - Resolving

    private suspend fun recommendationContext(): RecommendationContext {
        val history = runCatching { usage.stats() }.getOrDefault(emptyList())
        return RecommendationContext(currentProfile(), languages, priority, history)
    }

    /** The model to use now, honoring a pinned choice. */
    suspend fun model(role: ModelRole, language: String?): ModelDescriptor? = isolated {
        val selection = runCatching { usage.selection(role) }.getOrDefault(SelectionMode.Automatic)
        val installed = installedModels()
        if (selection is SelectionMode.Pinned) installed.firstOrNull { it.id == selection.id }?.let { return@isolated it }
        engine.automaticModel(role, installed, language, recommendationContext())
    }

    fun folder(id: String): File? = installer.folder(id)

    internal suspend fun installedModels(): List<ModelDescriptor> {
        val snapshot = makeSnapshot()
        return catalog.models.filter { snapshot.isInstalled(it.id) }
    }

    // MARK: - State

    private suspend fun handle(id: String, state: InstallState) {
        val model = catalog.models.firstOrNull { it.id == id }
        if (state == InstallState.Ready && model != null) {
            prepare(model)
        } else {
            overrides[id] = state
            publish()
        }
    }

    /** Loads a model once before it counts as ready, so that a broken download never shows as installed. */
    private suspend fun prepare(model: ModelDescriptor) {
        overrides[model.id] = InstallState.Preparing
        publish()
        arbiter.acquire()
        try {
            val runner = engines(model.runtime) ?: throw TranscriptionException(TranscriptionError.MODEL_NOT_INSTALLED)
            runner.prepare(model, installer.folder(model.id))
            runner.unload()
            overrides[model.id] = InstallState.Ready
        } catch (_: Exception) {
            overrides[model.id] = InstallState.Failed(InstallFailure.PREPARE_FAILED)
        } finally {
            withContext(NonCancellable) { arbiter.release() }
        }
        publish()
    }

    private suspend fun installSystemAssets(model: ModelDescriptor) {
        overrides[model.id] = InstallState.Preparing
        publish()
        try {
            for (language in languages) if (language in model.languages) systemAssets(model).install(language)
            overrides[model.id] = InstallState.Ready
        } catch (_: Exception) {
            overrides[model.id] = InstallState.Failed(InstallFailure.UNAVAILABLE)
        }
        publish()
    }

    private suspend fun currentProfile(): DeviceProfile = profile ?: device.profile().also { profile = it }

    private suspend fun publish() {
        snapshotFlow.value = makeSnapshot()
    }

    suspend fun makeSnapshot(): ModelsSnapshot {
        val context = recommendationContext()
        val condition = device.condition()
        val states = catalog.models.associate { it.id to systemOrInstallerState(it) }
        val fits = HashMap<ModelRole, List<ModelFit>>()
        val selections = HashMap<ModelRole, SelectionMode>()
        for (role in ModelRole.entries) {
            fits[role] = engine.recommend(role, catalog.models, context)
            selections[role] = runCatching { usage.selection(role) }.getOrDefault(SelectionMode.Automatic)
        }
        val suggestions = rules.suggestions(catalog.models, states.filterValues { it == InstallState.Ready }.keys, context, condition, now())
        return ModelsSnapshot(
            context.device, condition, RightNow.evaluate(condition), fits, states, selections,
            suggestions.filter { it.id !in dismissed }, priority,
        )
    }

    private fun systemAssets(model: ModelDescriptor): SystemSpeechAssets =
        if (model.runtime == ModelRuntime.APPLE_LANGUAGE) languageAssets ?: assets else assets

    private suspend fun systemOrInstallerState(model: ModelDescriptor): InstallState {
        overrides[model.id]?.let { return it }
        if (!model.isSystemManaged) return installer.state(model.id)
        for (language in languages) {
            if (language in model.languages && systemAssets(model).isInstalled(language)) return InstallState.Ready
        }
        return InstallState.NotInstalled
    }

    private fun seconds(from: Instant, to: Instant): Double = Duration.between(from, to).toNanos() / 1e9
}
