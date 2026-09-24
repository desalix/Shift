//
//  MonthExporter.swift
//  Shift
//

import Foundation

/// Builds the spreadsheet export for one or more months.
///
/// Only work entries are exported: the file is a record of shifts and pay,
/// not a copy of the calendar. Entries belong to the month they *start* in,
/// the same rule the Income tab uses, so an export and the paycheck it came
/// from always agree.
enum MonthExporter {
    /// One line of the sheet: Date, Name, Start, End, Total time, Income.
    nonisolated struct Row: Equatable {
        var name: String
        var start: Date
        var end: Date
        var minutes: Int
        /// Nil when the shift doesn't track pay — an empty cell, as the app
        /// shows a dash rather than €0.
        var earningsCents: Int?

        var cells: [SpreadsheetWriter.Cell] {
            [
                .date(start),
                .text(name),
                .time(start),
                .time(end),
                .duration(minutes: minutes),
                earningsCents.map { .euros(cents: $0) } ?? .empty,
            ]
        }
    }

    /// Wide enough for a date, a typical shift name, and the numbers.
    nonisolated static let columnWidths: [Double] = [12, 28, 8, 8, 11, 11]

    /// The header row, in the app's language.
    static var header: [String] {
        [
            String(localized: "Date", comment: "Export spreadsheet column: the day of the shift."),
            String(localized: "Name", comment: "Export spreadsheet column: the shift's title."),
            String(localized: "Start", comment: "Export spreadsheet column: start time."),
            String(localized: "End", comment: "Export spreadsheet column: end time."),
            String(localized: "Total time", comment: "Export spreadsheet column: the shift's length."),
            String(localized: "Income", comment: "Export spreadsheet column: what the shift earned."),
        ]
    }

    struct AvailableMonth: Equatable {
        var start: Date
        var entryCount: Int
    }

    /// Months that contain at least one work entry, newest first.
    static func availableMonths(for events: [Event], calendar: Calendar) -> [AvailableMonth] {
        let counts = Dictionary(grouping: events.filter { $0.type == .work }) {
            CalendarMath.startOfMonth(for: $0.startDate, calendar: calendar)
        }
        .mapValues(\.count)

        return counts
            .map { AvailableMonth(start: $0.key, entryCount: $0.value) }
            .sorted { $0.start > $1.start }
    }

    /// The work entries of the given months, oldest first. Months are
    /// identified by any date inside them.
    static func rows(events: [Event], months: [Date], calendar: Calendar) -> [Row] {
        let starts = Set(months.map { CalendarMath.startOfMonth(for: $0, calendar: calendar) })

        return events
            .filter { event in
                event.type == .work
                    && starts.contains(CalendarMath.startOfMonth(for: event.startDate, calendar: calendar))
            }
            .sorted { $0.startDate < $1.startDate }
            // A closure, not `.map(row(from:))`: an unapplied method reference
            // drops the main-actor isolation the models need.
            .map { row(from: $0) }
    }

    /// The finished `.xlsx`.
    nonisolated static func spreadsheet(header: [String], rows: [Row], calendar: Calendar) -> Data {
        SpreadsheetWriter.workbook(
            header: header,
            rows: rows.map(\.cells),
            columnWidths: columnWidths,
            calendar: calendar
        )
    }

    /// `Shift-2026-08.xlsx` for one month, `Shift-2026-06_to_2026-08.xlsx` for a
    /// range.
    static func fileName(for months: [Date], calendar: Calendar) -> String {
        let keys = Set(months.map { CalendarMath.startOfMonth(for: $0, calendar: calendar) })
            .sorted()
            .map { monthKey(for: $0, calendar: calendar) }

        guard let first = keys.first, let last = keys.last else { return "Shift.xlsx" }
        return first == last ? "Shift-\(first).xlsx" : "Shift-\(first)_to_\(last).xlsx"
    }

    static func monthKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private static func row(from event: Event) -> Row {
        Row(
            // `displayTitle`, so an untitled shift reads "Untitled", not blank.
            name: event.displayTitle,
            start: event.startDate,
            end: event.endDate,
            minutes: event.durationInMinutes,
            earningsCents: event.compensationType == nil ? nil : event.earningsInCents
        )
    }
}
