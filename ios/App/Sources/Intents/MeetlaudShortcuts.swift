import AppIntents

/// What Siri, Shortcuts, and the Action Button list without any setup.
struct MeetlaudShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleRecordingIntent(),
            phrases: ["Record with \(.applicationName)", "Record a meeting in \(.applicationName)"],
            shortTitle: "Record or stop",
            systemImageName: "mic.fill",
        )
        AppShortcut(
            intent: StopRecordingIntent(),
            phrases: ["Stop recording in \(.applicationName)"],
            shortTitle: "Stop recording",
            systemImageName: "stop.fill",
        )
        AppShortcut(
            intent: MarkMomentIntent(),
            phrases: ["Mark this moment in \(.applicationName)"],
            shortTitle: "Mark this moment",
            systemImageName: "flag.fill",
        )
        AppShortcut(
            intent: OpenLastMeetingIntent(),
            phrases: ["Open the last meeting in \(.applicationName)"],
            shortTitle: "Open the last meeting",
            systemImageName: "doc.text",
        )
    }
}
