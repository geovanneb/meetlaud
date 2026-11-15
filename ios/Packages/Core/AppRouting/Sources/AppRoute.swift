import Domain
import Foundation

/// Top-level destinations, in side menu order.
public enum Destination: String, CaseIterable, Hashable, Sendable {
    case home, library, ask, tools, settings, help

    /// Destinations shown above the divider in the side menu.
    public static let primary: [Destination] = [.home, .library, .ask, .tools]
    /// Destinations shown below the divider in the side menu.
    public static let secondary: [Destination] = [.settings, .help]
}

/// Every place the app can navigate to. Taps, widgets, Shortcuts, and notifications all use this type.
public enum AppRoute: Hashable, Sendable {
    /// Shows the recording entry point.
    ///
    /// This never starts capture. Any app on the device can open a `meetlaud://` URL, so a URL must not be
    /// able to turn on the microphone. Capture starts from a user tap or an App Intent. See D-024.
    case record
    case recording(RecordingID, at: TimeInterval?)
    case ask(recording: RecordingID?)
    case askFolder(FolderID)
    /// A new chat that answers the way a skill says. The id comes from a tap in Tools, never from a URL.
    case askSkill(String)
    case modelSettings
    case search
    case trash
    case calendar
    case preferences
    case networkActivity
    case licenses
    case people
    case memory
    case storage
    case notifications
    case calendars
    case vocabulary
    case privacy
    case about
    case helpCenter

    public var destination: Destination {
        switch self {
        case .record, .calendar: .home
        case .recording, .search, .trash, .askFolder: .library
        case .ask, .askSkill: .ask
        case .modelSettings, .preferences, .networkActivity, .licenses, .people, .memory, .storage, .notifications,
             .vocabulary, .calendars,
             .privacy, .about, .helpCenter: .settings
        }
    }

    /// Whether this route pushes a screen, instead of only selecting a destination.
    public var isPushed: Bool {
        switch self {
        case .record, .ask(recording: nil): false
        default: true
        }
    }
}
