import Foundation

/// The days a calendar shows. Everything follows the `Calendar` it is given, so that the week starts where the
/// person's region starts it.
public enum CalendarGrid {
    public static let daysInWeek = 7
    /// Always six rows, so that the page does not change height between months.
    public static let daysInMonthGrid = 42

    public static func week(containing date: Date, calendar: Calendar) -> [Date] {
        days(from: startOfWeek(containing: date, calendar: calendar), count: daysInWeek, calendar: calendar)
    }

    public static func month(containing date: Date, calendar: Calendar) -> [Date] {
        let first = startOfMonth(containing: date, calendar: calendar)
        return days(
            from: startOfWeek(containing: first, calendar: calendar),
            count: daysInMonthGrid,
            calendar: calendar,
        )
    }

    public static func startOfMonth(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// The first day of each month from `before` months ago to `after` months ahead.
    public static func months(around date: Date, before: Int, after: Int, calendar: Calendar) -> [Date] {
        let start = startOfMonth(containing: date, calendar: calendar)
        return (-before ... after).compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
    }

    /// One letter per day, in the order of the grid.
    public static func weekdayLetters(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// By calendar days and not by seconds, because a day is not always 24 hours long.
    private static func days(from start: Date, count: Int, calendar: Calendar) -> [Date] {
        (0 ..< count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}
