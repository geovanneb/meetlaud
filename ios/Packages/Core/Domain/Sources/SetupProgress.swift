import Foundation

public extension ModelsSnapshot {
    /// The one-tap setup as one figure, while any part of it is on its way. Nil otherwise.
    /// Installed models count as received, so the figure never goes back when one of them finishes.
    var setupProgress: SetupProgress? {
        let models = recommendedSetup.filter { !$0.isSystemManaged }
        let states = models.map { state(of: $0.id) }
        guard states.contains(where: \.isInFlight) else { return nil }
        var received: Int64 = 0
        var total: Int64 = 0
        for (model, state) in zip(models, states) {
            switch state {
            case .notInstalled, .failed:
                continue
            case .queued, .waitingForWiFi:
                break
            case let .downloading(bytes, _), let .paused(bytes, _):
                received += min(bytes, model.totalBytes)
            case .verifying, .preparing, .selfTest, .ready:
                received += model.totalBytes
            }
            total += model.totalBytes
        }
        return SetupProgress(received: received, total: total, phase: SetupProgress.Phase(states))
    }
}

/// How far the one-tap setup has come.
public struct SetupProgress: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// At least one file is moving, or about to.
        case downloading
        /// Nothing moves until Wi-Fi is back.
        case waitingForWiFi
        /// Nothing moves until the person resumes.
        case paused
        /// Every file is here. What remains is checking and preparing.
        case finishing

        init(_ states: [InstallState]) {
            func any(_ match: (InstallState) -> Bool) -> Bool {
                states.contains(where: match)
            }
            if any({
                if case .downloading = $0 {
                    true
                } else {
                    $0 == .queued
                }
            }) {
                self = .downloading
            } else if any({ $0 == .waitingForWiFi }) {
                self = .waitingForWiFi
            } else if any({
                if case .paused = $0 {
                    true
                } else {
                    false
                }
            }) {
                self = .paused
            } else {
                self = .finishing
            }
        }
    }

    public var received: Int64
    public var total: Int64
    public var phase: Phase

    public init(received: Int64, total: Int64, phase: Phase) {
        self.received = received
        self.total = total
        self.phase = phase
    }

    public var fraction: Double {
        total > 0 ? min(Double(received) / Double(total), 1) : 0
    }
}
