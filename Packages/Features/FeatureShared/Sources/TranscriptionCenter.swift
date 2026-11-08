import Domain
import Foundation
import Localization
import Observation

public enum AutoTranscribe: String, CaseIterable, Sendable {
    case ask, always, never

    public static let storageKey = "transcription.auto"

    public var title: String {
        switch self {
        case .ask: L10n.Transcript.autoAsk
        case .always: L10n.Transcript.autoAlways
        case .never: L10n.Transcript.autoNever
        }
    }
}

public enum TranscribeOutcome: Sendable {
    case started
    /// No installed model can do this. The user needs to get one.
    case needsModel
}

/// Shows and starts transcription work from any screen. There is one for the life of the app.
@MainActor
@Observable
public final class TranscriptionCenter {
    public private(set) var progress: [RecordingID: JobProgress] = [:]
    @ObservationIgnored private let coordinator: TranscriptionCoordinator
    @ObservationIgnored private let manager: ModelManager
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(coordinator: TranscriptionCoordinator, manager: ModelManager) {
        self.coordinator = coordinator
        self.manager = manager
        task = Task { [weak self] in
            for await progress in coordinator.updates {
                self?.progress = progress
            }
        }
    }

    deinit {
        task?.cancel()
    }

    public func transcribe(
        _ id: RecordingID,
        language: String?,
        whenCharging: Bool = false,
    ) async -> TranscribeOutcome {
        guard let model = await manager.model(for: .transcription, language: language) else { return .needsModel }
        try? await coordinator.enqueue(id, modelID: model.id, language: language, whenCharging: whenCharging)
        return .started
    }

    /// Nil when no model can transcribe this, which the start itself reports.
    public func plan(duration: TimeInterval, language: String?) async -> TranscribePlan? {
        guard let model = await manager.model(for: .transcription, language: language) else { return nil }
        let snapshot = await manager.makeSnapshot()
        let speed = snapshot.fits[.transcription]?.first { $0.model.id == model.id }?.speed ?? .unknown
        return TranscribePlan(
            duration: duration, speed: speed, rightNow: snapshot.rightNow, isCharging: snapshot.condition.isCharging,
        )
    }

    public func cancel(_ id: RecordingID) async {
        try? await coordinator.cancel(id)
    }

    public func restore(_ version: TranscriptVersion) async {
        try? await coordinator.restore(version)
    }
}
