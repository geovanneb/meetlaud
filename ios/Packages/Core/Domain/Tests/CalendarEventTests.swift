@testable import Domain
import Foundation
import Testing

struct CalendarEventTests {
    private func event(title: String, attendees: [String] = []) -> CalendarEvent {
        CalendarEvent(id: "1", title: title, start: .now, end: .now, attendees: attendees)
    }

    @Test func `a busy block with no title and nobody says nothing`() {
        #expect(!event(title: "").hasDetails)
        #expect(!event(title: "  \n").hasDetails)
    }

    @Test func `a meeting with people is kept even with no title`() {
        let meeting = event(title: "", attendees: ["Ana"])
        #expect(meeting.hasDetails)
        #expect(!meeting.hasTitle)
    }
}

struct CalendarGridTests {
    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    private func numbers(_ days: [Date], _ calendar: Calendar) -> [Int] {
        days.map { calendar.component(.day, from: $0) }
    }

    @Test func `a week starts where the region starts it`() {
        let sunday = calendar(firstWeekday: 1)
        #expect(numbers(CalendarGrid.week(containing: date(2026, 11, 7, in: sunday), calendar: sunday), sunday) == [
            1,
            2,
            3,
            4,
            5,
            6,
            7,
        ])
        let monday = calendar(firstWeekday: 2)
        #expect(numbers(CalendarGrid.week(containing: date(2026, 11, 7, in: monday), calendar: monday), monday) == [
            2,
            3,
            4,
            5,
            6,
            7,
            8,
        ])
    }

    @Test func `a month is always six rows, with its neighbors around it`() {
        let calendar = calendar(firstWeekday: 1)
        let december = CalendarGrid.month(containing: date(2026, 12, 15, in: calendar), calendar: calendar)
        #expect(december.count == CalendarGrid.daysInMonthGrid)
        #expect(numbers(Array(december.prefix(3)), calendar) == [29, 30, 1])
        #expect(numbers(Array(december.suffix(2)), calendar) == [8, 9])
    }

    @Test func `the letters follow the first day of the week`() {
        #expect(CalendarGrid.weekdayLetters(calendar: calendar(firstWeekday: 1)).first == "S")
        #expect(CalendarGrid.weekdayLetters(calendar: calendar(firstWeekday: 2)).first == "M")
    }

    @Test func `months run across a year`() {
        let calendar = calendar(firstWeekday: 1)
        let months = CalendarGrid.months(
            around: date(2026, 11, 7, in: calendar),
            before: 1,
            after: 2,
            calendar: calendar,
        )
        #expect(months.map { calendar.component(.month, from: $0) } == [10, 11, 12, 1])
    }

    @Test func `a day that changes the clock is still one day`() {
        var calendar = calendar(firstWeekday: 1)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let week = CalendarGrid.week(containing: date(2026, 11, 1, in: calendar), calendar: calendar)
        #expect(numbers(week, calendar) == [1, 2, 3, 4, 5, 6, 7])
    }
}
