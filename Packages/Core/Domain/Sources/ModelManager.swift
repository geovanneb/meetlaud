import Foundation

/// Apple's speech models belong to iOS, and are requested by language.
public protocol SystemSpeechAssets: Sendable {
    func isInstalled(language: String) async -> Bool
    func install(language: String) async throws
}

/// Everything the AI models screens show.
public struct ModelsSnapshot: Sendable, Equatable {
    public var device: DeviceProfile
    public var condition: DeviceCondition
    public var rightNow: RightNow
    public var fits: [ModelRole: [ModelFit]]
    public var states: [String: InstallState]
    public var selections: [ModelRole: SelectionMode]
    public var suggestions: [AdvisorSuggestion]
    public var priority: Priority

    public func state(of id: String) -> InstallState {
        states[id] ?? .notInstalled
    }

    public func isInstalled(_ id: String) -> Bool {
        state(of: id) == .ready
    }

    /// The models that make up the one-tap setup: the best fit for each role with models available.
    public var recommendedSetup: [ModelDescriptor] {
        var seen: Set<String> = []
        return ModelRole.allCases.compactMap { role in
            fits[role]?.first { $0.label >= .good }?.model
        }
        .filter { seen.insert($0.id).inserted }
    }

    public var missingFromSetup: [ModelDescriptor] {
        recommendedSetup.filter { !isInstalled($0.id) && !$0.isSystemManaged }
    }
}

/// Connects the catalog, the installer, and the device, and keeps one current recommendation.
public actor ModelManager {
    let catalog: any ModelCatalog
    let installer: any ModelInstaller
    private let usage: any ModelUsageStore
    fileprivate let device: any DeviceMonitor
    private let assets: any SystemSpeechAssets
    private let languageAssets: (any SystemSpeechAssets)?
    private var hasAskedForSearchModel = false
    let engines: @Sendable (ModelRuntime) -> (any ModelRunner)?
    let arbiter: ModelArbiter
    private let defaults: UserDefaults
    let now: @Sendable () -> Date
    private let engine = RecommendationEngine()
    private let rules = AdvisorRules()

    private var profile: DeviceProfile?
    private var overrides: [String: InstallState] = [:]
    private var dismissed: Set<String>
    private var tasks: [Task<Void, Never>] = []

    private static let dismissedKey = "models.dismissedSuggestions"
    private static let priorityKey = "models.priority"
    private static let languagesKey = "models.languages"

    public nonisolated let snapshots: AsyncStream<ModelsSnapshot>
    private let continuation: AsyncStream<ModelsSnapshot>.Continuation

    public init(
        catalog: any ModelCatalog,
        installer: any ModelInstaller,
        usage: any ModelUsageStore,
        device: any DeviceMonitor,
        assets: any SystemSpeechAssets,
        languageAssets: (any SystemSpeechAssets)? = nil,
        arbiter: ModelArbiter,
        defaults: UserDefaults = .standard,
        engines: @escaping @Sendable (ModelRuntime) -> (any ModelRunner)?,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.catalog = catalog
        self.installer = installer
        self.usage = usage
        self.device = device
        self.assets = assets
        self.languageAssets = languageAssets
        self.arbiter = arbiter
        self.defaults = defaults
        self.engines = engines
        self.now = now
        dismissed = Set(defaults.stringArray(forKey: Self.dismissedKey) ?? [])
        (snapshots, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Starts watching. Everything after this is event driven.
    public func start() async {
        await installer.reconnect()
        await publish()
        let events = installer.events
        let changes = device.changes
        tasks.append(Task { [weak self] in
            for await event in events {
                await self?.handle(event.id, event.state)
            }
        })
        tasks.append(Task { [weak self] in
            for await _ in changes {
                await self?.publish()
            }
        })
    }

    public var priority: Priority {
        defaults.string(forKey: Self.priorityKey).flatMap(Priority.init) ?? .balanced
    }

    public func setPriority(_ priority: Priority) async {
        defaults.set(priority.rawValue, forKey: Self.priorityKey)
        await publish()
    }

    public var languages: [String] {
        defaults.stringArray(forKey: Self.languagesKey) ?? Self.deviceLanguages
    }

    public func setLanguages(_ languages: [String]) async {
        defaults.set(languages, forKey: Self.languagesKey)
        await publish()
    }

    private static var deviceLanguages: [String] {
        let supported = ["en", "ja", "pt", "es"]
        let preferred = Locale.preferredLanguages
            .compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        let matches = preferred.filter { supported.contains($0) }
        return matches.isEmpty ? ["en"] : Array(Set(matches)).sorted()
    }

    // MARK: - Actions

    public func install(_ model: ModelDescriptor, allowsCellular: Bool = false) async {
        if model.isSystemManaged {
            await installSystemAssets(model)
        } else {
            await installer.install(model, allowsCellular: allowsCellular)
        }
    }

    /// Search is better with these, and they come from iOS, so nobody should have to go looking for them. Once per
    /// launch.
    public func installSearchModelIfNeeded() async {
        guard !hasAskedForSearchModel else { return }
        hasAskedForSearchModel = true
        for model in catalog.models where model.roles.contains(.search) && model.isSystemManaged {
            if await systemOrInstallerState(model) != .ready {
                await installSystemAssets(model)
            }
        }
    }

    /// Part of erasing everything. Apple's models belong to iOS and stay.
    public func removeAllModels() async {
        for id in await installer.installedIDs() {
            try? await installer.remove(id)
        }
        await publish()
    }

    public func installRecommended(allowsCellular: Bool = false) async {
        let snapshot = await makeSnapshot()
        // The smallest first, so that the app becomes useful as soon as possible.
        for model in snapshot.missingFromSetup.sorted(by: { $0.totalBytes < $1.totalBytes }) {
            await install(model, allowsCellular: allowsCellular)
        }
    }

    public func pause(_ id: String) async {
        await installer.pause(id)
    }

    public func cancel(_ id: String) async {
        await installer.cancel(id)
    }

    public func remove(_ id: String) async throws {
        try await installer.remove(id)
        overrides[id] = nil
        for role in ModelRole.allCases where try await usage.selection(for: role) == .pinned(id) {
            try await usage.setSelection(.automatic, for: role)
        }
        await publish()
    }

    public func select(_ mode: SelectionMode, for role: ModelRole) async throws {
        try await usage.setSelection(mode, for: role)
        await publish()
    }

    public func dismiss(_ suggestion: AdvisorSuggestion) async {
        dismissed.insert(suggestion.id)
        defaults.set(Array(dismissed), forKey: Self.dismissedKey)
        await publish()
    }

    /// Times one pass of a clip, and records it. Speed is what the device can tell us. Quality is not.
    public func runSpeedTest(_ modelID: String, clip: AudioWindow, passes: Int) async throws -> ModelRunStat {
        guard let model = catalog.models.first(where: { $0.id == modelID }),
              let runner = engines(model.runtime) as? any TranscriptionEngine
        else { throw TranscriptionError.modelNotInstalled }
        // A test is optional, so it gives way to real work instead of waiting for it.
        guard await arbiter.tryAcquire() else { throw ModelArbiterError.busy }
        let folder = installer.folder(for: modelID)
        let started: Date
        do {
            try await runner.prepare(model: model, folder: folder)
            started = now()
            for _ in 0 ..< max(passes, 1) {
                try Task.checkCancellation()
                _ = try await runner.transcribe(clip, language: languages.first)
            }
        } catch {
            await runner.unload()
            await arbiter.release()
            throw error
        }
        await runner.unload()
        await arbiter.release()
        let stat = ModelRunStat(
            modelID: modelID,
            audioDuration: (clip.end - clip.start) * Double(max(passes, 1)),
            wallTime: now().timeIntervalSince(started),
            outcome: .completed,
            date: now(),
        )
        try await usage.insert(stat)
        await publish()
        return stat
    }
}

// MARK: - Resolving

extension ModelManager {
    private func recommendationContext() async -> RecommendationContext {
        let profile = await currentProfile()
        let history = await (try? usage.stats()) ?? []
        return RecommendationContext(device: profile, languages: languages, priority: priority, history: history)
    }

    /// The model to use now, honoring a pinned choice.
    public func model(for role: ModelRole, language: String?) async -> ModelDescriptor? {
        let selection = await (try? usage.selection(for: role)) ?? .automatic
        if case let .pinned(id) = selection, let model = await installedModels().first(where: { $0.id == id }) {
            return model
        }
        let installed = await installedModels()
        return await engine.automaticModel(
            role: role, installed: installed, language: language, context: recommendationContext(),
        )
    }

    public nonisolated func folder(for id: String) -> URL? {
        installer.folder(for: id)
    }

    func installedModels() async -> [ModelDescriptor] {
        let snapshot = await makeSnapshot()
        return catalog.models.filter { snapshot.isInstalled($0.id) }
    }

    // MARK: - State

    private func handle(_ id: String, _ state: InstallState) async {
        if state == .ready, let model = catalog.models.first(where: { $0.id == id }) {
            await prepare(model)
        } else {
            overrides[id] = state
            await publish()
        }
    }

    /// Core ML compiles a model the first time it loads, so this runs before the model counts as ready.
    private func prepare(_ model: ModelDescriptor) async {
        overrides[model.id] = .preparing
        await publish()
        await arbiter.acquire()
        do {
            guard let runner = engines(model.runtime) else { throw TranscriptionError.modelNotInstalled }
            try await runner.prepare(model: model, folder: installer.folder(for: model.id))
            await runner.unload()
            overrides[model.id] = .ready
        } catch {
            overrides[model.id] = .failed(.prepareFailed)
        }
        await arbiter.release()
        await publish()
    }

    private func installSystemAssets(_ model: ModelDescriptor) async {
        overrides[model.id] = .preparing
        await publish()
        do {
            for language in languages where model.languages.contains(language) {
                try await systemAssets(for: model).install(language: language)
            }
            overrides[model.id] = .ready
        } catch {
            overrides[model.id] = .failed(.unavailable)
        }
        await publish()
    }

    private func currentProfile() async -> DeviceProfile {
        if let profile {
            return profile
        }
        let value = await device.profile()
        profile = value
        return value
    }

    private func publish() async {
        await continuation.yield(makeSnapshot())
    }

    public func makeSnapshot() async -> ModelsSnapshot {
        let context = await recommendationContext()
        let condition = await device.condition()
        var states: [String: InstallState] = [:]
        for model in catalog.models {
            states[model.id] = await systemOrInstallerState(model)
        }
        var fits: [ModelRole: [ModelFit]] = [:]
        var selections: [ModelRole: SelectionMode] = [:]
        for role in ModelRole.allCases {
            fits[role] = engine.recommend(role: role, catalog: catalog.models, context: context)
            selections[role] = await (try? usage.selection(for: role)) ?? .automatic
        }
        let suggestions = rules.suggestions(
            catalog: catalog.models,
            installedIDs: Set(states.filter { $0.value == .ready }.keys),
            context: context,
            condition: condition,
            now: now(),
        )
        return ModelsSnapshot(
            device: context.device,
            condition: condition,
            rightNow: RightNow.evaluate(condition),
            fits: fits,
            states: states,
            selections: selections,
            suggestions: suggestions.filter { !dismissed.contains($0.id) },
            priority: priority,
        )
    }

    private func systemAssets(for model: ModelDescriptor) -> any SystemSpeechAssets {
        model.runtime == .appleLanguage ? languageAssets ?? assets : assets
    }

    private func systemOrInstallerState(_ model: ModelDescriptor) async -> InstallState {
        if let override = overrides[model.id] {
            return override
        }
        guard model.isSystemManaged else { return await installer.state(of: model.id) }
        for language in languages where model.languages.contains(language) {
            if await systemAssets(for: model).isInstalled(language: language) {
                return .ready
            }
        }
        return .notInstalled
    }
}
