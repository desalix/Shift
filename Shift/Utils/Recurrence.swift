//
//  Recurrence.swift
//  Shift
//

import Foundation

/// Expansion for the app's one native recurrence rule: repeat weekly on a set
/// of weekdays until an end date.
///
/// Anything more elaborate — skip alternate weeks, skip public holidays — is
/// deliberately *not* modelled here. Those are entered as individual occurrences
/// instead, which keeps the stored model simple and leaves every occurrence
/// independently editable.
enum Recurrence {
    /// The dates a weekly rule produces, as (start, end) pairs preserving the
    /// original time of day and duration.
    ///
    /// The first occurrence is included when its weekday is in `weekdays`.
    static func occurrences(
        start: Date,
        end: Date,
        weekdays: [Int],
        until: Date,
        calendar: Calendar,
        limit: Int = 400
    ) -> [(start: Date, end: Date)] {
        let selected = Set(weekdays).filter { (1 ... 7).contains($0) }
        guard !selected.isEmpty, until >= start else { return [] }

        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return [] }

        // Walk day by day from the start date, keeping the wall-clock time of
        // the original. Using `date(bySettingHour:)` rather than adding raw
        // intervals keeps 09:00 at 09:00 across a daylight-saving change.
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: start)
        let lastDay = calendar.startOfDay(for: until)

        var results: [(start: Date, end: Date)] = []
        var cursor = calendar.startOfDay(for: start)

        while cursor <= lastDay, results.count < limit {
            let weekday = calendar.component(.weekday, from: cursor)
            if selected.contains(weekday) {
                if let occurrenceStart = calendar.date(
                    bySettingHour: timeComponents.hour ?? 0,
                    minute: timeComponents.minute ?? 0,
                    second: timeComponents.second ?? 0,
                    of: cursor
                ), occurrenceStart >= start {
                    results.append((occurrenceStart, occurrenceStart.addingTimeInterval(duration)))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return results
    }

    /// Human-readable summary of a weekly rule, e.g. "Every Mon, Thu until 30 Sep".
    static func description(
        weekdays: [Int],
        until: Date,
        calendar: Calendar,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? []

        let names = weekdays.sorted().compactMap { index -> String? in
            let position = index - 1
            guard position >= 0, position < symbols.count else { return nil }
            return symbols[position]
        }

        let dayList = names.joined(separator: ", ")
        let endText = until.formatted(.dateTime.day().month(.abbreviated).locale(locale))
        return String(localized: "Every \(dayList) until \(endText)")
    }
}
