import Domain
@preconcurrency import EventKit
import Foundation

/// Adds to the Reminders app. Only ever runs from a person's explicit action, after they confirm.
public final class SystemRemindersProvider: RemindersProvider, @unchecked Sendable {
    /// Unchecked because EKEventStore is not marked Sendable. It is documented as safe across threads, and this holds
    /// no other state.
    private let store = EKEventStore()

    public init() {}

    public func add(title: String, notes: String?) async throws {
        guard await (try? store.requestFullAccessToReminders()) == true else { throw RemindersError.denied }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = store.defaultCalendarForNewReminders()
        try store.save(reminder, commit: true)
    }
}
