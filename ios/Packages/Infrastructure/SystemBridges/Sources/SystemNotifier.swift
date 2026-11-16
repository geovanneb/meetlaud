import Domain
import Foundation
import UserNotifications

/// Local notifications only. The app never registers for remote ones, so no server could ever send one.
public struct SystemNotifier: LocalNotifier {
    private static let reminderPrefix = "reminder."

    public init() {}

    public func requestAccess() async -> Bool {
        await (try? UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    public func notify(id: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil),
        )
    }

    public func scheduleReminders(for events: [CalendarEvent], title: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.reminderPrefix) },
        )
        for event in events {
            let delay = event.start.timeIntervalSinceNow - NotificationPreferences.reminderLead
            guard delay > 0 else { continue }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = event.title
            try? await center.add(UNNotificationRequest(
                identifier: Self.reminderPrefix + event.id,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false),
            ))
        }
    }
}
