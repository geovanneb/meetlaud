import Domain
import Foundation
import Localization
import Observation

/// The state of the AI model screens. There is one for the life of the app.
@MainActor
@Observable
public final class ModelsController {
    public private(set) var snapshot: ModelsSnapshot?
    public private(set) var networkLog: [NetworkLogEntry] = []
    public private(set) var languages: [String] = []
    public private(set) var testing: String?
    public private(set) var lastTest: ModelRunStat?
    public private(set) var lastLanguageTest: LanguageSpeed?
    public private(set) var lastSearchTest: SearchSpeed?
    public private(set) var testError: String?
    public private(set) var trials: [ModelTrial] = []
    /// The latest runs of one model on this device, speed tests and real jobs alike, newest first.
    public private(set) var history: [ModelRunStat] = []
    /// Recordings that can feed "Try on your audio", newest first.
    public private(set) var trialChoices: [Recording] = []
    public var trialRecording: RecordingID?
    public var showsSetup = false

    @ObservationIgnored private let manager: ModelManager
    @ObservationIgnored private let usage: any ModelUsageStore
    @ObservationIgnored private let clip: @Sendable () async -> AudioWindow?
    @ObservationIgnored private let trialRecordings: @Sendable () async -> [Recording]
    @ObservationIgnored private let trialClip: @Sendable (RecordingID) async -> AudioWindow?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var testTask: Task<Void, Never>?

    private static let hasSeenSetupKey = "models.hasSeenSetup"

    public init(
        manager: ModelManager,
        usage: any ModelUsageStore,
        clip: @escaping @Sendable () async -> AudioWindow?,
        trialRecordings: @escaping @Sendable () async -> [Recording] = { [] },
        trialClip: @escaping @Sendable (RecordingID) async -> AudioWindow? = { _ in nil },
    ) {
        self.manager = manager
        self.usage = usage
        self.clip = clip
        self.trialRecordings = trialRecordings
        self.trialClip = trialClip
        task = Task { [weak self] in
            await manager.start()
            await self?.refreshLanguages()
            for await snapshot in manager.snapshots {
                self?.snapshot = snapshot
            }
        }
    }

    deinit {
        task?.cancel()
    }

    private func refreshLanguages() async {
        languages = await manager.languages
    }

    /// The first launch offers the recommended setup once, and never insists.
    public func offerSetupIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: Self.hasSeenSetupKey) else { return }
        defaults.set(true, forKey: Self.hasSeenSetupKey)
        showsSetup = true
    }

    func refreshNetworkLog() async {
        networkLog = await (try? usage.networkLog()) ?? []
    }

    func installRecommended() {
        Task { await manager.installRecommended() }
    }

    func install(_ model: ModelDescriptor, allowsCellular: Bool = false) {
        Task { await manager.install(model, allowsCellular: allowsCellular) }
    }

    func pause(_ id: String) {
        Task { await manager.pause(id) }
    }

    func cancel(_ id: String) {
        Task { await manager.cancel(id) }
    }

    func remove(_ id: String) {
        Task { try? await manager.remove(id) }
    }

    func select(_ mode: SelectionMode, for role: ModelRole) {
        Task { try? await manager.select(mode, for: role) }
    }

    func setPriority(_ priority: Priority) {
        Task { await manager.setPriority(priority) }
    }

    func setLanguages(_ codes: [String]) {
        languages = codes
        Task { await manager.setLanguages(codes) }
    }

    func dismiss(_ suggestion: AdvisorSuggestion) {
        Task { await manager.dismiss(suggestion) }
    }

    /// Runs in the foreground only, and stops the moment the user cancels.
    func loadHistory(_ id: String) async {
        let runs = await (try? usage.stats()) ?? []
        history = Array(runs.filter { $0.modelID == id }.sorted { $0.date > $1.date }.prefix(5))
    }

    func runSpeedTest(_ id: String, sustained: Bool) {
        testing = id
        lastTest = nil
        testError = nil
        testTask = Task { [weak self] in
            guard let self else { return }
            defer { testing = nil }
            guard let clip = await clip() else {
                testError = L10n.Models.testFailed
                return
            }
            do {
                lastTest = try await manager.runSpeedTest(id, clip: clip, passes: sustained ? 8 : 1)
            } catch is CancellationError {
                return
            } catch ModelArbiterError.busy {
                testError = L10n.Models.testBusy
            } catch {
                testError = "\(L10n.Models.testFailed) (\(error.localizedDescription))"
            }
        }
    }

    /// Both models hear the start of the latest recording. Nothing is saved until a person picks one.
    /// Keeps the chosen recording when it still exists, and falls back to the newest one.
    func loadTrialChoices() async {
        trialChoices = await trialRecordings()
        if trialRecording.map({ id in !trialChoices.contains { $0.id == id } }) ?? true {
            trialRecording = trialChoices.first?.id
        }
    }

    func runTrial(_ ids: [String]) {
        testing = ids.first
        trials = []
        testError = nil
        testTask = Task { [weak self] in
            guard let self else { return }
            defer { testing = nil }
            guard let recording = trialRecording else {
                testError = L10n.Models.tryNoRecording
                return
            }
            guard let clip = await trialClip(recording) else {
                testError = L10n.Models.tryUnreadable
                return
            }
            do {
                trials = try await manager.tryModels(ids, on: clip)
            } catch is CancellationError {
                return
            } catch ModelArbiterError.busy {
                testError = L10n.Models.testBusy
            } catch {
                testError = "\(L10n.Models.testFailed) (\(error.localizedDescription))"
            }
        }
    }

    func runLanguageTest(_ id: String) {
        testing = id
        lastLanguageTest = nil
        testError = nil
        testTask = Task { [weak self] in
            guard let self else { return }
            defer { testing = nil }
            do {
                lastLanguageTest = try await manager.runLanguageTest(id)
            } catch is CancellationError {
                return
            } catch ModelArbiterError.busy {
                testError = L10n.Models.testBusy
            } catch {
                testError = "\(L10n.Models.testFailed) (\(error.localizedDescription))"
            }
        }
    }

    func runSearchTest(_ id: String) {
        testing = id
        lastSearchTest = nil
        testError = nil
        testTask = Task { [weak self] in
            guard let self else { return }
            defer { testing = nil }
            do {
                lastSearchTest = try await manager.runSearchTest(id)
            } catch ModelArbiterError.busy {
                testError = L10n.Models.testBusy
            } catch {
                testError = "\(L10n.Models.testFailed) (\(error.localizedDescription))"
            }
        }
    }

    /// A test uses the GPU, so it ends the moment the app stops being active.
    public func cancelSpeedTest() {
        testTask?.cancel()
        testing = nil
    }
}
