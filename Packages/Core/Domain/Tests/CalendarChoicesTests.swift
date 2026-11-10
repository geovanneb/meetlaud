@testable import Domain
import Foundation
import Testing
import TestSupport

final class CalendarChoicesTests {
    private let suite = "tests.calendars.\(UUID().uuidString)"
    private lazy var choices = CalendarChoices(suiteName: suite)

    deinit {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func provider() -> FakeCalendarProvider {
        let now = Date()
        return FakeCalendarProvider(
            access: .granted,
            events: [
                CalendarEvent(
                    id: "a", title: "Planning", start: now, end: now.addingTimeInterval(60), attendees: [],
                    calendarID: "work",
                ),
                CalendarEvent(
                    id: "b", title: "Dinner", start: now, end: now.addingTimeInterval(60), attendees: [],
                    calendarID: "home",
                ),
            ],
            sources: [
                CalendarSource(id: "work", title: "Work", account: "Exchange"),
                CalendarSource(id: "home", title: "Home", account: "iCloud"),
            ],
        )
    }

    private func titles(_ calendars: ChosenCalendars) async -> [String] {
        await calendars.events(from: .distantPast, to: .distantFuture).map(\.title)
    }

    @Test func `every calendar is used until the person leaves one out`() async {
        let calendars = ChosenCalendars(base: provider(), choices: choices)
        #expect(await titles(calendars) == ["Planning", "Dinner"])
        choices.setShown(false, for: "home")
        #expect(await titles(calendars) == ["Planning"])
        choices.setShown(true, for: "home")
        #expect(await titles(calendars) == ["Planning", "Dinner"])
    }

    /// The choice stores what is off, so a calendar added later in iOS shows up on its own.
    @Test func `a calendar the app has not seen before is shown`() {
        choices.setShown(false, for: "home")
        #expect(choices.isShown("new-account-calendar"))
        #expect(!choices.isShown("home"))
    }

    @Test func `turned off, nothing is read, and Home offers Connect again`() async {
        let calendars = ChosenCalendars(base: provider(), choices: choices)
        choices.isOn = false
        #expect(await titles(calendars).isEmpty)
        #expect(calendars.access == .undetermined)
        #expect(await calendars.calendars().count == 2, "Settings still lists them, to turn back on")
    }

    @Test func `connecting again turns calendars back on`() async {
        let calendars = ChosenCalendars(base: provider(), choices: choices)
        choices.isOn = false
        #expect(await calendars.requestAccess())
        #expect(choices.isOn)
        #expect(calendars.access == .granted)
        #expect(await titles(calendars) == ["Planning", "Dinner"])
    }
}
