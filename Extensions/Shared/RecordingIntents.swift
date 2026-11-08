import AppIntents
import Foundation

/// Starts or ends a recording, for one button: the Action Button, Control Center, and widgets.
///
/// Compiled into the app and the widget extension. The extension draws the button, and because this opens the app, the
/// work runs in the app's process. iOS only lets capture start from the foreground. See D-024 for why this may start
/// capture when a URL may not: only a person, or a Shortcut they set up, can run it.
struct ToggleRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Record or stop"
    static let description = IntentDescription("Starts a recording. If one is running, stops it.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingCommandBridge.send(.toggle)
        return .result()
    }
}

struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Record a meeting"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingCommandBridge.send(.start)
        return .result()
    }
}

struct OpenLastMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Open the last meeting"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingCommandBridge.send(.openLast)
        return .result()
    }
}
