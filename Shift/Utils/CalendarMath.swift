//
//  CalendarMath.swift
//  Shift
//

import Foundation

/// Date helpers for the fixed month grid. All of these take an explicit
/// `Calendar` so the first weekday follows the user's locale rather than a
/// hardcoded Sunday or Monday.
enum CalendarMath {
    /// Midnight on the first day of the month containing `date`.
    static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    /// Exclusive upper bound: midnight on the first day of the next month.
    static func startOfNextMonth(for date: Date, calendar: Calendar) -> Date {
        let start = startOfMonth(for: date, calendar: calendar)
        return calendar.date(byAdding: .month, value: 1, to: start) ?? start
    }

    static func month(byAdding value: Int, to date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .month, value: value, to: startOfMonth(for: date, calendar: calendar))
            ?? date
    }

    /// Every day shown in the month grid, including the leading and trailing
    /// days borrowed from the adjacent months so the grid is always full weeks.
    ///
    /// The grid is deliberately a whole number of weeks: the Home view is fixed
    /// and non-zoomable, so a ragged final row would just look broken.
    static func monthGridDays(for date: Date, calendar: Calendar) -> [Date] {
        let monthStart = startOfMonth(for: date, calendar: calendar)
        let monthEnd = startOfNextMonth(for: date, calendar: calendar)

        // How many days of the previous month pad the first row.
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7

        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: monthStart) else {
            return []
        }

        let daysInMonth = calendar.dateComponents([.day], from: monthStart, to: monthEnd).day ?? 30
        let total = leading + daysInMonth
        let weeks = Int((Double(total) / 7.0).rounded(.up))

        return (0 ..< (weeks * 7)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: gridStart)
        }
    }

    /// Localised one- or two-letter weekday headers, rotated to start on the
    /// calendar's first weekday.
    static func weekdaySymbols(calendar: Calendar, locale: Locale) -> [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        let symbols = formatter.veryShortStandaloneWeekdaySymbols
            ?? formatter.shortStandaloneWeekdaySymbols
            ?? ["S", "M", "T", "W", "T", "F", "S"]
        let offset = calendar.firstWeekday - 1
        guard offset > 0, offset < symbols.count else { return symbols }
        return Array(symbols[offset...] + symbols[..<offset])
    }

    /// Half-open day bounds, suitable for a SwiftData predicate.
    static func dayBounds(for date: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }
}
