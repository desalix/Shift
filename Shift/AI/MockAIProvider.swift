//
//  MockAIProvider.swift
//  Shift
//

import Foundation

/// An offline stand-in used when no API key is configured.
///
/// It is deliberately narrow — a small regex-driven parser, not a language
/// model — but it produces the same `AssistantProposal` values as the real
/// provider, so the whole propose-review-apply flow can be exercised (and
/// tested) without a key or a network.
struct MockAIProvider: AIProvider {
    func respond(
        to history: [AssistantMessage],
        context: AssistantContext
    ) async throws -> AssistantReply {
        // A touch of latency so the typing indicator behaves as it will in
        // production rather than flashing.
        try? await Task.sleep(for: .milliseconds(450))

        guard let prompt = history.last(where: { $0.role == .user })?.text.lowercased() else {
            return AssistantReply(text: Self.greeting, proposal: nil)
        }

        let calendar = Calendar.autoupdatingCurrent
        let timeZone = TimeZone(identifier: context.timeZoneIdentifier) ?? .current

        if history.last?.attachments.isEmpty == false {
            return AssistantReply(
                text: String(localized: "I can see you attached a file, but reading files needs a live connection. Add your Anthropic API key in Settings and I'll be able to pull the shifts out of it."),
                proposal: nil
            )
        }

        if prompt.contains("delete") || prompt.contains("remove") || prompt.contains("borrar") || prompt.contains("elimina") {
            return AssistantReply(
                text: String(localized: "Deleting entries needs a live connection so I can match exactly what you mean. Add your API key in Settings, or swipe an entry in the day view to delete it yourself."),
                proposal: nil
            )
        }

        guard let parsed = Self.parseShift(from: prompt, calendar: calendar, timeZone: timeZone, today: context.today) else {
            return AssistantReply(text: Self.help, proposal: nil)
        }

        let actions = parsed.occurrences.map { occurrence in
            AssistantAction.createEvent(
                EventSpec(
                    title: parsed.title,
                    type: parsed.rateCents == nil ? .calendar : .work,
                    startDate: occurrence.start,
                    endDate: occurrence.end,
                    address: nil,
                    compensationType: parsed.rateCents == nil ? nil : .hourly,
                    hourlyRateCents: parsed.rateCents,
                    fixedRateCents: nil,
                    schoolKind: nil,
                    subjectName: nil,
                    notes: nil
                )
            )
        }

        let summary = actions.count == 1
            ? String(localized: "Here's the entry I'd add. Review it and tap Apply.")
            : String(localized: "Here are the \(actions.count) entries I'd add. Review them and tap Apply.")

        return AssistantReply(
            text: summary + "\n\n" + String(localized: "(Demo mode — add your API key in Settings for the full assistant.)"),
            proposal: AssistantProposal(actions: actions)
        )
    }

    // MARK: - Canned copy

    private static var greeting: String {
        String(localized: "Tell me what to add and I'll draft it for you.")
    }

    private static var help: String {
        String(localized: """
        I'm running in demo mode, so I only understand simple requests like:

        • "Add a shift Thursday 14:30-19:00 at 12.50/h"
        • "Every Monday 9-17"

        Add your Anthropic API key in Settings and I'll handle files, recurring rules with exceptions, edits, and deletions properly.
        """)
    }

    // MARK: - Parsing

    private struct ParsedShift {
        var title: String
        var rateCents: Int?
        var occurrences: [(start: Date, end: Date)]
    }

    /// Looks for a time range, an optional weekday, and an optional rate.
    private static func parseShift(
        from prompt: String,
        calendar: Calendar,
        timeZone: TimeZone,
        today: Date
    ) -> ParsedShift? {
        guard let range = timeRange(in: prompt) else { return nil }

        var calendar = calendar
        calendar.timeZone = timeZone

        let weekday = self.weekday(in: prompt, calendar: calendar)
        let isRepeating = prompt.contains("every") || prompt.contains("cada") || prompt.contains("todos")
        let rate = rateCents(in: prompt)

        // Anchor on the next occurrence of the named weekday, or today when
        // none was given.
        let anchor: Date
        if let weekday {
            anchor = nextDate(weekday: weekday, onOrAfter: today, calendar: calendar)
        } else {
            anchor = today
        }

        let weekCount = isRepeating ? 4 : 1
        var occurrences: [(start: Date, end: Date)] = []

        for week in 0 ..< weekCount {
            guard let day = calendar.date(byAdding: .day, value: week * 7, to: anchor),
                  let start = calendar.date(bySettingHour: range.startHour, minute: range.startMinute, second: 0, of: day)
            else { continue }

            var end = calendar.date(bySettingHour: range.endHour, minute: range.endMinute, second: 0, of: day) ?? start
            // An end earlier than the start means the shift runs past midnight.
            if end <= start { end = end.addingTimeInterval(24 * 3600) }
            occurrences.append((start, end))
        }

        guard !occurrences.isEmpty else { return nil }

        return ParsedShift(
            title: rate == nil ? String(localized: "Event") : String(localized: "Shift"),
            rateCents: rate,
            occurrences: occurrences
        )
    }

    private static func timeRange(in prompt: String) -> (startHour: Int, startMinute: Int, endHour: Int, endMinute: Int)? {
        // "14:30-19:00", "14.30 to 19", "9-17"
        let pattern = #"(\d{1,2})(?:[:.](\d{2}))?\s*(?:-|–|—|to|a|hasta)\s*(\d{1,2})(?:[:.](\d{2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt))
        else { return nil }

        func value(_ index: Int) -> Int? {
            guard let range = Range(match.range(at: index), in: prompt) else { return nil }
            return Int(prompt[range])
        }

        guard let startHour = value(1), let endHour = value(3),
              (0 ... 23).contains(startHour), (0 ... 23).contains(endHour)
        else { return nil }

        let startMinute = value(2) ?? 0
        let endMinute = value(4) ?? 0
        guard (0 ... 59).contains(startMinute), (0 ... 59).contains(endMinute) else { return nil }

        return (startHour, startMinute, endHour, endMinute)
    }

    private static func rateCents(in prompt: String) -> Int? {
        let pattern = #"(\d{1,4})(?:[.,](\d{1,2}))?\s*(?:€|eur|euros?)?\s*(?:/|per\s+|por\s+)?\s*(?:h|hr|hour|hora)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
              let wholeRange = Range(match.range(at: 1), in: prompt),
              let whole = Int(prompt[wholeRange])
        else { return nil }

        var cents = whole * 100
        if let fractionRange = Range(match.range(at: 2), in: prompt) {
            let text = String(prompt[fractionRange])
            let padded = text.count == 1 ? text + "0" : text
            cents += Int(padded) ?? 0
        }
        return cents > 0 ? cents : nil
    }

    /// Matches English and Spanish weekday names, returning a `Calendar`
    /// weekday index (1 = Sunday).
    private static func weekday(in prompt: String, calendar: Calendar) -> Int? {
        let names: [(names: [String], index: Int)] = [
            (["sunday", "domingo"], 1),
            (["monday", "lunes"], 2),
            (["tuesday", "martes"], 3),
            (["wednesday", "miercoles", "miércoles"], 4),
            (["thursday", "thursdays", "jueves"], 5),
            (["friday", "viernes"], 6),
            (["saturday", "sabado", "sábado"], 7),
        ]
        for entry in names where entry.names.contains(where: { prompt.contains($0) }) {
            return entry.index
        }
        return nil
    }

    private static func nextDate(weekday: Int, onOrAfter date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        for offset in 0 ..< 7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if calendar.component(.weekday, from: candidate) == weekday { return candidate }
        }
        return start
    }
}
