import Domain
import Foundation
import Observation

@MainActor
@Observable
public final class HomeModel {
    public private(set) var recordings: [Recording] = []
    public private(set) var events: [CalendarEvent] = []
    public private(set) var calendarAccess: CalendarAccess
    /// Closed Connect card: Upcoming shows a line that leads to Settings instead.
    public private(set) var isConnectHidden: Bool
    private(set) var calendarEvents: [CalendarEvent] = []

    @ObservationIgnored private let calendar: any CalendarProvider
    @ObservationIgnored private let choices: CalendarChoices
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(
        store: any RecordingStore,
        calendar: any CalendarProvider,
        choices: CalendarChoices = CalendarChoices(),
    ) {
        self.calendar = calendar
        self.choices = choices
        calendarAccess = calendar.access
        isConnectHidden = choices.isConnectHidden
        task = Task { [weak self] in
            for await recordings in store.observeRecordings() {
                self?.recordings = recordings.filter { $0.deletedAt == nil }
            }
        }
    }

    deinit {
        task?.cancel()
    }

    public func refreshEvents() async {
        calendarAccess = calendar.access
        isConnectHidden = choices.isConnectHidden
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        events = await calendar.events(from: now, to: end).filter(\.hasDetails)
    }

    func hideConnect() {
        choices.isConnectHidden = true
        isConnectHidden = true
    }

    func connectCalendar() async {
        _ = await calendar.requestAccess()
        await refreshEvents()
    }

    /// What Home shows in Upcoming. The full week lives in Calendar view.
    var nextEvents: [CalendarEvent] {
        Array(events.prefix(3))
    }

    // MARK: - Calendar view

    /// Everything the month's grid can show, neighbors included, so that a day is ready as soon as it is tapped.
    func loadCalendar(month: Date) async {
        let grid = CalendarGrid.month(containing: month, calendar: .current)
        guard let first = grid.first, let last = grid.last,
              let end = Calendar.current.date(byAdding: .day, value: 1, to: last) else { return }
        calendarEvents = await calendar.events(from: first, to: end).filter(\.hasDetails)
    }

    func events(on day: Date) -> [CalendarEvent] {
        calendarEvents.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
    }

    func recordings(on day: Date) -> [Recording] {
        recordings.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: day) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func hasContent(on day: Date) -> Bool {
        !events(on: day).isEmpty || !recordings(on: day).isEmpty
    }
}
