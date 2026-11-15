import Domain
import Localization

/// The device status in the same words on every screen.
public extension RightNow {
    var title: String {
        switch self {
        case .great: L10n.Models.nowGreat
        case .good: L10n.Models.nowGood
        case .limited: L10n.Models.nowLimited
        case .paused: L10n.Models.nowPaused
        }
    }

    var detail: String? {
        let reason: Reason? = switch self {
        case let .good(value), let .limited(value): value
        default: nil
        }
        return reason.map {
            switch $0 {
            case .warm: L10n.Models.conditionWarm
            case .hot: L10n.Models.conditionHot
            case .lowPower: L10n.Models.conditionLowPower
            case .lowBattery: L10n.Models.conditionLowBattery
            case .lowMemory: L10n.Models.conditionLowMemory
            }
        }
    }
}
