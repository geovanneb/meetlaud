import Foundation

/// What a person should know before a long transcription starts: how long it should take, and whether the device is
/// in a good state for it.
public struct TranscribePlan: Equatable, Sendable {
    /// Expected minutes, as a range when the speed is only estimated. Nil when nothing is known about the speed.
    public let minutes: ClosedRange<Int>?
    public let rightNow: RightNow
    public let isCharging: Bool

    /// A job this long is worth a word first, even when the device is fine.
    public static let longJobMinutes = 10

    public init(duration: TimeInterval, speed: SpeedEvidence, rightNow: RightNow, isCharging: Bool) {
        self.rightNow = rightNow
        self.isCharging = isCharging
        minutes = switch speed {
        case let .measured(value): Self.minutes(duration, value).map { $0 ... $0 }
        case let .estimated(low, high):
            // The faster speed gives the shorter time.
            Self.minutes(duration, high)
                .flatMap { short in Self.minutes(duration, low).map { short ... max(short, $0) } }
        case .unknown: nil
        }
    }

    /// Short jobs on a device in good shape just start.
    public var deservesNote: Bool {
        rightNow != .great || (minutes?.upperBound ?? 0) >= Self.longJobMinutes
    }

    /// Waiting for a charger only helps when there is no charger yet.
    public var canWaitForCharger: Bool {
        !isCharging
    }

    private static func minutes(_ duration: TimeInterval, _ speed: Double) -> Int? {
        guard speed > 0, duration > 0 else { return nil }
        return max(1, Int((duration / speed / 60).rounded(.up)))
    }
}
