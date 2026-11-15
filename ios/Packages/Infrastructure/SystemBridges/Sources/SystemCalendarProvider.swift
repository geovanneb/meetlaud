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
                    calendarID: event.calendar?.calendarIdentifier ?? "",
                )
            }
    }

    public func calendars() async -> [CalendarSource] {
        guard access == .granted else { return [] }
        return store.calendars(for: .event)
            .map { calendar in
                CalendarSource(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    account: calendar.source?.title ?? "",
                    accountID: calendar.source?.sourceIdentifier,
                    tint: Self.tint(of: calendar.cgColor),
                )
            }
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    private static func tint(of color: CGColor?) -> CalendarSource.Tint? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let rgb = color?.converted(to: space, intent: .defaultIntent, options: nil),
              let parts = rgb.components, parts.count >= 3 else { return nil }
        return CalendarSource.Tint(red: Double(parts[0]), green: Double(parts[1]), blue: Double(parts[2]))
    }

    private static func wasDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }
}
