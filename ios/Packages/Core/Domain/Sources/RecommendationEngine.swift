import Foundation

public enum FitLabel: Int, Comparable, Sendable {
    case unsupported, notRecommended, maySlow, good, best

    public static func < (lhs: FitLabel, rhs: FitLabel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum FitReason: Hashable, Sendable {
    case bestForDevice
    case worksWell
    case belowTargetSpeed
    case notEnoughMemory
    case unstableHere
    case languageNotCovered(String)
}

public enum SpeedEvidence: Hashable, Sendable {
    /// Scaled from reference devices. Shown as a range.
    case estimated(low: Double, high: Double)
    /// Measured on this device.
    case measured(Double)
    case unknown

    /// A cautious single number for decisions.
    var conservative: Double? {
        switch self {
        case let .estimated(low, _): low
        case let .measured(value): value
        case .unknown: nil
        }
    }
}

public struct ModelFit: Identifiable, Hashable, Sendable {
    public let model: ModelDescriptor
    public let label: FitLabel
    public let reason: FitReason
    public let speed: SpeedEvidence

    public var id: String {
        model.id
    }
}

/// What a recommendation depends on, apart from the models themselves.
public struct RecommendationContext: Sendable {
    public var device: DeviceProfile
    public var languages: [String]
    public var priority: Priority
    public var history: [ModelRunStat]

    public init(device: DeviceProfile, languages: [String], priority: Priority, history: [ModelRunStat]) {
        self.device = device
        self.languages = languages
        self.priority = priority
        self.history = history
    }
}

/// Decides which models suit this device. Pure and deterministic, so that a table of cases can prove it.
public struct RecommendationEngine: Sendable {
    /// Transcription slower than this feels broken: one hour would take 20 minutes.
    public static let minimumSpeedX = 3.0
    /// Peak memory must fit this share of the device, because iOS kills apps well before all of it.
    static let memoryBudget = 0.6
    /// Two kills mean that the model does not fit this device, whatever the numbers say.
    static let killsToMarkUnstable = 2
    /// Estimates are scaled across devices, so they carry this margin either way.
    static let estimateMargin = 0.3

    public init() {}

    public func recommend(
        role: ModelRole,
        catalog: [ModelDescriptor],
        context: RecommendationContext,
    ) -> [ModelFit] {
        let fits = catalog
            .filter { $0.roles.contains(role) }
            .map { assess($0, context: context) }
            .sorted { lhs, rhs in
                if lhs.label != rhs.label {
                    return lhs.label > rhs.label
                }
                return score(lhs, context: context) > score(rhs, context: context)
            }
        guard let top = fits.first, top.label == .good else { return fits }
        let best = ModelFit(model: top.model, label: .best, reason: .bestForDevice, speed: top.speed)
        return [best] + fits.dropFirst()
    }

    /// Picks the installed model to use for a language in Automatic mode.
    public func automaticModel(
        role: ModelRole,
        installed: [ModelDescriptor],
        language: String?,
        context: RecommendationContext,
    ) -> ModelDescriptor? {
        var context = context
        context.languages = language.map { [$0] } ?? []
        return recommend(role: role, catalog: installed, context: context)
            .first { $0.label >= .maySlow }?
            .model
    }

    private func assess(_ model: ModelDescriptor, context: RecommendationContext) -> ModelFit {
        let device = context.device
        let languages = context.languages
        let history = context.history
        let runs = history.filter { $0.modelID == model.id }
        let speed = speedEvidence(for: model, device: device, runs: runs)

        func fit(_ label: FitLabel, _ reason: FitReason) -> ModelFit {
            ModelFit(model: model, label: label, reason: reason, speed: speed)
        }

        if Double(model.minMemoryMB) > Double(device.physicalMemoryMB) {
            return fit(.unsupported, .notEnoughMemory)
        }
        if let missing = languages.first(where: { !model.supports(language: $0) }) {
            return fit(.notRecommended, .languageNotCovered(missing))
        }
        if runs.count(where: { $0.outcome == .killed }) >= Self.killsToMarkUnstable {
            return fit(.notRecommended, .unstableHere)
        }
        if Double(model.minMemoryMB) > Double(device.physicalMemoryMB) * Self.memoryBudget {
            return fit(.notRecommended, .notEnoughMemory)
        }
        if let value = speed.conservative, value < Self.minimumSpeedX {
            return fit(.maySlow, .belowTargetSpeed)
        }
        return fit(.good, .worksWell)
    }

    private func speedEvidence(
        for model: ModelDescriptor,
        device: DeviceProfile,
        runs: [ModelRunStat],
    ) -> SpeedEvidence {
        if let latest = runs.filter({ $0.outcome == .completed }).max(by: { $0.date < $1.date }) {
            return .measured(latest.speedX)
        }
        let reference = model.reference.first { $0.device == device.identifier } ?? model.reference.first
        guard let reference else { return .unknown }
        // A probe compares this device with the reference one. Without it, the reference is the best guess.
        let scale = device.probeScore > 0 && reference.probeScore > 0
            ? device.probeScore / reference.probeScore
            : 1
        let value = reference.speedX * scale
        return .estimated(low: value * (1 - Self.estimateMargin), high: value * (1 + Self.estimateMargin))
    }

    private func score(_ fit: ModelFit, context: RecommendationContext) -> Double {
        let codes = context.languages.isEmpty ? Array(fit.model.quality.keys) : context.languages
        let total = codes.compactMap { fit.model.quality[$0] }.reduce(0, +)
        let quality = codes.isEmpty ? 0 : Double(total) / Double(codes.count)
        let speed = min((fit.speed.conservative ?? Self.minimumSpeedX) / 10, 2)
        // Smaller wins ties, since a download costs the user something.
        let size = Double(fit.model.totalBytes) / 100_000_000_000
        return switch context.priority {
        case .quality: quality * 3 + speed - size
        case .balanced: quality * 2 + speed * 2 - size
        case .speed: quality + speed * 3 - size
        }
    }
}

public enum RightNow: Sendable, Equatable {
    case great
    case good(Reason)
    case limited(Reason)
    case paused

    public enum Reason: Sendable, Equatable {
        case warm, hot, lowPower, lowBattery, lowMemory
    }

    /// Whether a heavy job should start, or wait for the device.
    public var allowsHeavyWork: Bool {
        self != .paused
    }

    public static func evaluate(_ condition: DeviceCondition, requiredMemoryMB: Int = 0) -> RightNow {
        if condition.thermal == .critical {
            return .paused
        }
        if condition.thermal == .serious {
            return .limited(.hot)
        }
        if condition.isLowPower {
            return .limited(.lowPower)
        }
        if requiredMemoryMB > 0, condition.availableMemoryMB < requiredMemoryMB {
            return .limited(.lowMemory)
        }
        if !condition.isCharging, condition.batteryLevel < 0.2 {
            return .limited(.lowBattery)
        }
        if condition.thermal == .fair {
            return .good(.warm)
        }
        if !condition.isCharging, condition.batteryLevel < 0.3 {
            return .good(.lowBattery)
        }
        return .great
    }
}

public enum AdvisorSuggestion: Hashable, Sendable, Identifiable {
    case betterFit(role: ModelRole, modelID: String)
    case languageNotCovered(language: String, role: ModelRole)
    case unstable(modelID: String, alternativeID: String?)
    case tooSlow(modelID: String)
    case unusedModel(modelID: String, bytes: Int64)

    public var id: String {
        switch self {
        case let .betterFit(role, model): "better-\(role.rawValue)-\(model)"
        case let .languageNotCovered(language, role): "language-\(language)-\(role.rawValue)"
        case let .unstable(model, _): "unstable-\(model)"
        case let .tooSlow(model): "slow-\(model)"
        case let .unusedModel(model, _): "unused-\(model)"
        }
    }
}

/// Turns the device's situation into suggestions. It only ever suggests: nothing here changes anything.
public struct AdvisorRules: Sendable {
    public static let unusedAfter: TimeInterval = 60 * 24 * 60 * 60
    /// Below this, a model is worth flagging only if the disk is tight.
    static let lowSpaceBytes: Int64 = 2_000_000_000

    private let engine = RecommendationEngine()

    public init() {}

    public func suggestions(
        catalog: [ModelDescriptor],
        installedIDs: Set<String>,
        context: RecommendationContext,
        condition: DeviceCondition,
        now: Date,
    ) -> [AdvisorSuggestion] {
        let languages = context.languages
        let history = context.history
        var result: [AdvisorSuggestion] = []
        let installed = catalog.filter { installedIDs.contains($0.id) }

        for role in ModelRole.allCases {
            let fits = engine.recommend(role: role, catalog: catalog, context: context)
            guard !fits.isEmpty else { continue }
            if let language = languages.first(where: { code in
                !fits.contains { $0.model.supports(language: code) && installedIDs.contains($0.model.id) }
            }), installed.contains(where: { $0.roles.contains(role) }) {
                result.append(.languageNotCovered(language: language, role: role))
            }
            let usable = installed.filter { $0.roles.contains(role) }
            if let best = fits.first(where: { $0.label == .best }), !installedIDs.contains(best.model.id),
               !usable.isEmpty
            {
                result.append(.betterFit(role: role, modelID: best.model.id))
            }
        }

        for model in installed {
            let runs = history.filter { $0.modelID == model.id }
            if runs.count(where: { $0.outcome == .killed }) >= RecommendationEngine.killsToMarkUnstable {
                let alternative = catalog.first {
                    $0.id != model.id && $0.minMemoryMB < model.minMemoryMB
                        && !Set($0.roles).isDisjoint(with: model.roles)
                }
                result.append(.unstable(modelID: model.id, alternativeID: alternative?.id))
            }
            if let latest = runs.filter({ $0.outcome == .completed }).max(by: { $0.date < $1.date }),
               latest.speedX < 1
            {
                result.append(.tooSlow(modelID: model.id))
            }
            let lastUse = runs.map(\.date).max()
            if !model.isSystemManaged, condition.freeBytes < Self.lowSpaceBytes,
               lastUse.map({ now.timeIntervalSince($0) > Self.unusedAfter }) ?? true
            {
                result.append(.unusedModel(modelID: model.id, bytes: model.totalBytes))
            }
        }
        return result
    }
}
