package com.meetlaud.app.feature.models

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.meetlaud.app.localization.L10n
import com.meetlaud.domain.AdvisorSuggestion
import com.meetlaud.domain.AudioWindow
import com.meetlaud.domain.LanguageSpeed
import com.meetlaud.domain.ModelBusyException
import com.meetlaud.domain.ModelDescriptor
import com.meetlaud.domain.ModelManager
import com.meetlaud.domain.ModelRole
import com.meetlaud.domain.ModelRunStat
import com.meetlaud.domain.ModelTrial
import com.meetlaud.domain.ModelUsageStore
import com.meetlaud.domain.ModelsSnapshot
import com.meetlaud.domain.NetworkLogEntry
import com.meetlaud.domain.Preferences
import com.meetlaud.domain.Priority
import com.meetlaud.domain.Recording
import com.meetlaud.domain.RecordingID
import com.meetlaud.domain.SearchSpeed
import com.meetlaud.domain.SelectionMode
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/** The state of the AI model screens. There is one for the life of the app, as ModelsController.swift. */
class ModelsController(
    private val manager: ModelManager,
    private val usage: ModelUsageStore,
    private val scope: CoroutineScope,
    private val clip: suspend () -> AudioWindow?,
    private val trialRecordings: suspend () -> List<Recording> = { emptyList() },
    private val trialClip: suspend (RecordingID) -> AudioWindow? = { null },
) {
    var snapshot by mutableStateOf<ModelsSnapshot?>(null)
        private set
    var networkLog by mutableStateOf<List<NetworkLogEntry>>(emptyList())
        private set
    var languages by mutableStateOf<List<String>>(emptyList())
        private set
    var testing by mutableStateOf<String?>(null)
        private set
    var lastTest by mutableStateOf<ModelRunStat?>(null)
        private set
    var lastLanguageTest by mutableStateOf<LanguageSpeed?>(null)
        private set
    var lastSearchTest by mutableStateOf<SearchSpeed?>(null)
        private set
    var testError by mutableStateOf<String?>(null)
        private set
    var trials by mutableStateOf<List<ModelTrial>>(emptyList())
        private set
    /** The latest runs of one model on this device, speed tests and real jobs alike, newest first. */
    var history by mutableStateOf<List<ModelRunStat>>(emptyList())
        private set
    /** Recordings that can feed "Try on your audio", newest first. */
    var trialChoices by mutableStateOf<List<Recording>>(emptyList())
        private set
    var trialRecording by mutableStateOf<RecordingID?>(null)
    var showsSetup by mutableStateOf(false)

    private var testJob: Job? = null

    private companion object {
        const val HAS_SEEN_SETUP_KEY = "models.hasSeenSetup"
    }

    init {
        scope.launch {
            manager.start()
            languages = manager.languages
            manager.snapshots.collect { value -> if (value != null) snapshot = value }
        }
    }

    /** The first launch offers the recommended setup once, and never insists. */
    fun offerSetupIfNeeded(defaults: Preferences) {
        if (defaults.bool(HAS_SEEN_SETUP_KEY) == true) return
        defaults.setBool(HAS_SEEN_SETUP_KEY, true)
        showsSetup = true
    }

    suspend fun refreshNetworkLog() {
        networkLog = runCatching { usage.networkLog() }.getOrDefault(emptyList())
    }

    suspend fun clearNetworkLog() {
        runCatching { usage.clearNetworkLog() }
        refreshNetworkLog()
    }

    fun installRecommended() { scope.launch { manager.installRecommended() } }
    fun resumeSetup() { scope.launch { manager.resumeSetup() } }
    fun install(model: ModelDescriptor, allowsCellular: Boolean = false) { scope.launch { manager.install(model, allowsCellular) } }
    fun pause(id: String) { scope.launch { manager.pause(id) } }
    fun cancel(id: String) { scope.launch { manager.cancel(id) } }
    fun remove(id: String) { scope.launch { runCatching { manager.remove(id) } } }
    fun select(mode: SelectionMode, role: ModelRole) { scope.launch { runCatching { manager.select(mode, role) } } }
    fun setPriority(priority: Priority) { scope.launch { manager.setPriority(priority) } }
    fun dismiss(suggestion: AdvisorSuggestion) { scope.launch { manager.dismiss(suggestion) } }

    fun changeLanguages(codes: List<String>) {
        languages = codes
        scope.launch { manager.setLanguages(codes) }
    }

    suspend fun loadHistory(id: String) {
        val runs = runCatching { usage.stats() }.getOrDefault(emptyList())
        history = runs.filter { it.modelID == id }.sortedByDescending { it.date }.take(5)
    }

    /** Runs a test in the foreground only, and stops the moment the person cancels. */
    private fun test(id: String?, block: suspend () -> Unit) {
        testing = id
        testError = null
        testJob = scope.launch {
            try {
                block()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: ModelBusyException) {
                testError = L10n.Models.testBusy
            } catch (error: Exception) {
                testError = "${L10n.Models.testFailed} (${error.localizedMessage ?: error.javaClass.simpleName})"
            } finally {
                testing = null
            }
        }
    }

    fun runSpeedTest(id: String, sustained: Boolean) {
        lastTest = null
        test(id) {
            val window = clip()
            if (window == null) testError = L10n.Models.testFailed
            else lastTest = manager.runSpeedTest(id, window, if (sustained) 8 else 1)
        }
    }

    /** Keeps the chosen recording when it still exists, and falls back to the newest one. */
    suspend fun loadTrialChoices() {
        trialChoices = trialRecordings()
        if (trialRecording?.let { id -> trialChoices.none { it.id == id } } != false) trialRecording = trialChoices.firstOrNull()?.id
    }

    /** Both models hear the start of the chosen recording. Nothing is saved until a person picks one. */
    fun runTrial(ids: List<String>) {
        trials = emptyList()
        test(ids.firstOrNull()) {
            val recording = trialRecording
            if (recording == null) {
                testError = L10n.Models.tryNoRecording
                return@test
            }
            val window = trialClip(recording)
            if (window == null) testError = L10n.Models.tryUnreadable
            else trials = manager.tryModels(ids, window)
        }
    }

    fun runLanguageTest(id: String) {
        lastLanguageTest = null
        test(id) { lastLanguageTest = manager.runLanguageTest(id) }
    }

    fun runSearchTest(id: String) {
        lastSearchTest = null
        test(id) { lastSearchTest = manager.runSearchTest(id) }
    }

    /** A test uses the GPU, so it ends the moment the app stops being active. */
    fun cancelSpeedTest() {
        testJob?.cancel()
        testing = null
    }
}
