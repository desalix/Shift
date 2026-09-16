//
//  MonthExporter.swift
//  Shift
//

import Foundation

/// Builds the JSON export for one or more months.
///
/// Entries belong to the month they *start* in, the same rule the Income tab
/// uses, so an export and the paycheck it came from always agree.
enum MonthExporter {
    struct Document: Codable, Equatable {
        var app: String
        var version: Int
        var exportedAt: Date
        var currency: String
        var timeZone: String
        var months: [Month]
    }

    struct Month: Codable, Equatable {
        /// `yyyy-MM`.
        var month: String
        var entries: [Entry]
    }

    struct Entry: Codable, Equatable {
        var id: UUID
        var title: String
        var type: String
        var start: Date
        var end: Date
        var durationMinutes: Int
        var earningsCents: Int
        var address: String?
        var compensationType: String?
        var hourlyRateCents: Int?
        var fixedRateCents: Int?
        var schoolKind: String?
        var subject: String?
        var notes: String?
        var isRecurring: Bool
        var recurrenceId: UUID?
    }

    struct AvailableMonth: Equatable {
        var start: Date
        var entryCount: Int
    }

    /// Months that contain at least one entry, newest first.
    static func availableMonths(for events: [Event], calendar: Calendar) -> [AvailableMonth] {
        let counts = Dictionary(grouping: events) {
            CalendarMath.startOfMonth(for: $0.startDate, calendar: calendar)
        }
        .mapValues(\.count)

        return counts
            .map { AvailableMonth(start: $0.key, entryCount: $0.value) }
            .sorted { $0.start > $1.start }
    }

    /// The export for the given months, oldest first, each month's entries in
    /// start order. Months are identified by any date inside them.
    static func makeDocument(
        events: [Event],
        months: [Date],
        calendar: Calendar,
        now: Date = .now
    ) -> Document {
        let starts = Set(months.map { CalendarMath.startOfMonth(for: $0, calendar: calendar) }).sorted()

        let exportedMonths = starts.map { start in
            let end = CalendarMath.startOfNextMonth(for: start, calendar: calendar)
            let entries = events
                .filter { $0.startDate >= start && $0.startDate < end }
                .sorted { $0.startDate < $1.startDate }
                // A closure, not `.map(entry(from:))`: an unapplied method
                // reference drops the main-actor isolation the models need.
                .map { entry(from: $0) }
            return Month(month: monthKey(for: start, calendar: calendar), entries: entries)
        }

        return Document(
            app: "Shift",
            version: 1,
            exportedAt: now,
            currency: Money.currencyCode,
            timeZone: calendar.timeZone.identifier,
            months: exportedMonths
        )
    }

    /// Pretty, key-sorted JSON with ISO-8601 dates carrying the export's UTC
    /// offset, so times read the way they appear in the app.
    static func encode(_ document: Document, timeZone: TimeZone) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            // Pin the offset separator: the default is `.omitted`, which renders
            // "+0200" and changed behaviour between OS versions. "+02:00" is the
            // form readers expect, so state it rather than inherit it.
            let style = Date.ISO8601FormatStyle(timeZone: timeZone).timeZoneSeparator(.colon)
            try container.encode(date.formatted(style))
        }
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> Document {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Document.self, from: data)
    }

    /// `Shift-2026-08.json` for one month, `Shift-2026-06_to_2026-08.json` for a
    /// range.
    static func fileName(for months: [Date], calendar: Calendar) -> String {
        let keys = Set(months.map { CalendarMath.startOfMonth(for: $0, calendar: calendar) })
            .sorted()
            .map { monthKey(for: $0, calendar: calendar) }

        guard let first = keys.first, let last = keys.last else { return "Shift.json" }
        return first == last ? "Shift-\(first).json" : "Shift-\(first)_to_\(last).json"
    }

    static func monthKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private static func entry(from event: Event) -> Entry {
        Entry(
            id: event.id,
            // `displayTitle`, so an exam exports as "Calculus Exam" rather than "".
            title: event.displayTitle,
            type: event.type.rawValue,
            start: event.startDate,
            end: event.endDate,
            durationMinutes: event.durationInMinutes,
            earningsCents: event.earningsInCents,
            address: event.address,
            compensationType: event.compensationType?.rawValue,
            hourlyRateCents: event.hourlyRateCents,
            fixedRateCents: event.fixedRateCents,
            schoolKind: event.schoolKind?.rawValue,
            subject: event.subject?.name,
            notes: event.notes,
            isRecurring: event.isRecurring,
            recurrenceId: event.recurrenceID
        )
    }
}
