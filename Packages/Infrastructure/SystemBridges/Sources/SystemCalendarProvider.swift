import Domain
@preconcurrency import EventKit
import Foundation

/// Reads the calendars already on the device, Google accounts included, with no sign-in and no network of ours.
public final class SystemCalendarProvider: CalendarProvider, @unchecked Sendable {
    private let store = EKEventStore()

    public init() {}

    public var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    public func requestAccess() async -> Bool {
        await (try? store.requestFullAccessToEvents()) ?? false
    }

    public func events(from start: Date, to end: Date) async -> [CalendarEvent] {
        guard access == .granted else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && !Self.wasDeclined($0) }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                CalendarEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "",
                    start: event.startDate,
                    end: event.endDate,
                    attendees: (event.attendees ?? []).compactMap(\.name),
                )
            }
    }

    private static func wasDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }
}
