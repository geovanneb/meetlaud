import Domain
import Foundation
import Observation

/// Which calendars the app reads. Home picks up a change the next time it loads its events.
@MainActor
@Observable
public final class CalendarsModel {
    public struct Account: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let calendars: [CalendarSource]
    }

    public private(set) var access: CalendarAccess
    /// Nil until the first load, so the screen does not flash "No calendars" while it asks iOS.
    public private(set) var accounts: [Account]?
    public private(set) var hidden: Set<String>

    @ObservationIgnored private let provider: any CalendarProvider
    @ObservationIgnored private let choices: CalendarChoices

    /// `provider` is the one the rest of the app reads, so that "off" here is off everywhere.
    public init(provider: any CalendarProvider, choices: CalendarChoices) {
        self.provider = provider
        self.choices = choices
        access = provider.access
        hidden = choices.hidden
    }

    var isUsing: Bool {
        access == .granted
    }

    func load() async {
        access = provider.access
        hidden = choices.hidden
        let calendars = await provider.calendars()
        accounts = Dictionary(grouping: calendars, by: \.accountID)
            .map { id, calendars in
                Account(
                    id: id,
                    name: calendars.first?.account ?? "",
                    calendars: calendars.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending },
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// On asks iOS when it has not been asked yet. Off stops reading at once, and iOS keeps its permission.
    func setUsing(_ isOn: Bool) async {
        if isOn {
            _ = await provider.requestAccess()
        } else {
            choices.isOn = false
        }
        await load()
    }

    func isShown(_ calendar: CalendarSource) -> Bool {
        !hidden.contains(calendar.id)
    }

    func setShown(_ isShown: Bool, for calendar: CalendarSource) {
        choices.setShown(isShown, for: calendar.id)
        hidden = choices.hidden
    }
}
