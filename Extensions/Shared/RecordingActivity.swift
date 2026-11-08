import ActivityKit
import AppIntents
import Foundation

/// Compiled into both the app and the widget extension, because both must agree on these types.
struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable {
            case recording, paused, interrupted, finishing
        }

        var phase: Phase
        /// When the timer would have started had the recording never paused. Lets the system run the clock.
        var timerStart: Date
        var recorded: TimeInterval
    }

    var title: String
}

/// Commands from outside the app's screens. They run in the app's process.
enum RecordingCommand: Sendable {
    case togglePause, stop, mark, start, toggle, openLast
}

@MainActor
enum RecordingCommandBridge {
    /// A press of the Action Button can launch the app, and arrive before the app is ready. It must not get lost.
    private static var waiting: [RecordingCommand] = []

    static var handler: (@MainActor (RecordingCommand) -> Void)? {
        didSet {
            guard let handler else { return }
            let commands = waiting
            waiting = []
            commands.forEach(handler)
        }
    }

    static func send(_ command: RecordingCommand) {
        if let handler {
            handler(command)
        } else {
            waiting.append(command)
        }
    }
}

struct TogglePauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or resume recording"

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingCommandBridge.send(.togglePause)
        return .result()
    }
}

struct StopRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop recording"

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingCommandBridge.send(.stop)
        return .result()
    }
}

struct MarkMomentIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark this moment"

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingCommandBridge.send(.mark)
        return .result()
    }
}
