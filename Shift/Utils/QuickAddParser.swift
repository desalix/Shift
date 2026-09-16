//
//  QuickAddParser.swift
//  Shift
//

import Foundation

/// Turns a typed line like "work thursday 9-17 at 12.50/h" into the fields of an
/// entry.
///
/// Entirely on device, instant, and free — no network, no account, no model. It
/// understands far less than a language model would, but it covers the request
/// people actually make dozens of times a month, and it works on every phone the
/// app runs on.
///
/// The result is only ever used to *pre-fill the editor*, never to write an
/// entry directly. The user sees what was understood and corrects it before
/// saving, so a misparse costs a glance rather than a wrong shift.
enum QuickAddParser {
    struct Result: Equatable {
        var title: String
        var type: EventType
        var startDate: Date
        var endDate: Date
        var hourlyRateCents: Int?
        /// Set when the text named a weekday and asked to repeat, so the editor
        /// can switch its weekly rule on with that day already ticked.
        var repeatsOnWeekday: Int?
    }

    /// Returns nil when there is no time range to anchor an entry on — better to
    /// leave the form untouched than to invent a time the user never said.
    static func parse(
        _ text: String,
        calendar: Calendar,
        timeZone: TimeZone = .current,
        now: Date = Date()
    ) -> Result? {
        let lowered = text.lowercased()
        guard let range = timeRange(in: lowered) else { return nil }

        var calendar = calendar
        calendar.timeZone = timeZone

        let rate = rateCents(in: lowered)
        let weekday = self.weekday(in: lowered)
        let repeats = lowered.contains("every") || lowered.contains("cada") || lowered.contains("todos")
        let type = eventType(in: lowered, hasRate: rate != nil)

        let day = anchorDay(in: lowered, weekday: weekday, calendar: calendar, now: now)

        guard let start = calendar.date(
            bySettingHour: range.startHour, minute: range.startMinute, second: 0, of: day
        ) else { return nil }

        var end = calendar.date(
            bySettingHour: range.endHour, minute: range.endMinute, second: 0, of: day
        ) ?? start
        // An end at or before the start means the shift runs past midnight.
        if end <= start { end = end.addingTimeInterval(24 * 3600) }

        return Result(
            title: title(from: text, type: type),
            type: type,
            startDate: start,
            endDate: end,
            hourlyRateCents: rate,
            repeatsOnWeekday: repeats ? weekday : nil
        )
    }

    // MARK: - Pieces

    /// "14:30-19:00", "14.30 to 19", "9-17", "de 9 a 17"
    static func timeRange(in text: String) -> (startHour: Int, startMinute: Int, endHour: Int, endMinute: Int)? {
        let pattern = #"(\d{1,2})(?:[:.](\d{2}))?\s*(?:-|–|—|to|a|hasta)\s*(\d{1,2})(?:[:.](\d{2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }

        func value(_ index: Int) -> Int? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Int(text[range])
        }

        guard let startHour = value(1), let endHour = value(3),
              (0 ... 23).contains(startHour), (0 ... 23).contains(endHour)
        else { return nil }

        let startMinute = value(2) ?? 0
        let endMinute = value(4) ?? 0
        guard (0 ... 59).contains(startMinute), (0 ... 59).contains(endMinute) else { return nil }

        return (startHour, startMinute, endHour, endMinute)
    }

    /// "12.50/h", "12,50 €/hora", "10 per hour"
    static func rateCents(in text: String) -> Int? {
        let pattern = #"(\d{1,4})(?:[.,](\d{1,2}))?\s*(?:€|eur|euros?)?\s*(?:/|per\s+|por\s+)\s*(?:h|hr|hour|hora)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let wholeRange = Range(match.range(at: 1), in: text),
              let whole = Int(text[wholeRange])
        else { return nil }

        var cents = whole * 100
        if let fractionRange = Range(match.range(at: 2), in: text) {
            let fraction = String(text[fractionRange])
            cents += Int(fraction.count == 1 ? fraction + "0" : fraction) ?? 0
        }
        return cents > 0 ? cents : nil
    }

    /// English and Spanish weekday names, returning a `Calendar` weekday index
    /// (1 = Sunday).
    static func weekday(in text: String) -> Int? {
        let names: [(names: [String], index: Int)] = [
            (["sunday", "domingo"], 1),
            (["monday", "lunes"], 2),
            (["tuesday", "martes"], 3),
            (["wednesday", "miercoles", "miércoles"], 4),
            (["thursday", "jueves"], 5),
            (["friday", "viernes"], 6),
            (["saturday", "sabado", "sábado"], 7),
        ]
        for entry in names where entry.names.contains(where: { text.contains($0) }) {
            return entry.index
        }
        return nil
    }

    private static func eventType(in text: String, hasRate: Bool) -> EventType {
        let school = ["exam", "examen", "class", "clase", "assignment", "trabajo de clase"]
        if school.contains(where: { text.contains($0) }) { return .school }

        let work = ["work", "shift", "turno", "trabajo", "curro"]
        if hasRate || work.contains(where: { text.contains($0) }) { return .work }

        return .calendar
    }

    /// Tomorrow, today, the next named weekday, or today when nothing was said.
    private static func anchorDay(
        in text: String,
        weekday: Int?,
        calendar: Calendar,
        now: Date
    ) -> Date {
        if text.contains("tomorrow") || text.contains("mañana") || text.contains("manana") {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
                ?? calendar.startOfDay(for: now)
        }

        guard let weekday else { return calendar.startOfDay(for: now) }

        let start = calendar.startOfDay(for: now)
        for offset in 0 ..< 7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if calendar.component(.weekday, from: candidate) == weekday { return candidate }
        }
        return start
    }

    /// Whatever text is left once the time, rate and scheduling words are taken
    /// out — that residue is usually the name. Falls back to a sensible default
    /// rather than leaving the title empty, which would fail validation.
    private static func title(from text: String, type: EventType) -> String {
        var remainder = text
        let strip = [
            #"\d{1,2}(?:[:.]\d{2})?\s*(?:-|–|—|to|a|hasta)\s*\d{1,2}(?:[:.]\d{2})?"#,
            #"\d{1,4}(?:[.,]\d{1,2})?\s*(?:€|eur|euros?)?\s*(?:/|per\s+|por\s+)\s*(?:h|hr|hour|hora)"#,
            #"(?i)\b(every|cada|todos|los|las|at|a las|de|from|desde|tomorrow|mañana|manana|today|hoy)\b"#,
            #"(?i)\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|lunes|martes|miércoles|miercoles|jueves|viernes|sábado|sabado|domingo)\b"#,
        ]
        for pattern in strip {
            remainder = remainder.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        let cleaned = remainder
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleaned.isEmpty { return cleaned.prefix(1).uppercased() + cleaned.dropFirst() }

        switch type {
        case .work: return String(localized: "Shift")
        case .school: return String(localized: "Class")
        case .calendar: return String(localized: "Event")
        }
    }
}
