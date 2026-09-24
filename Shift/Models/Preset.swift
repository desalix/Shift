//
//  Preset.swift
//  Shift
//

import Foundation
import SwiftData

/// A saved template that pre-fills the event editor. Every field is optional:
/// a preset may specify as much or as little as the user wants.
///
/// Deleting a preset only unlinks it from its events (nullify) — the events
/// themselves are real entries and must survive.
@Model
final class Preset {
    var id: UUID = UUID()
    var name: String = ""
    var typeRaw: String = EventType.work.rawValue
    var title: String?

    var compensationTypeRaw: String?
    var hourlyRateCents: Int?
    var fixedRateCents: Int?

    var schoolKindRaw: String?
    var address: String?
    var notes: String?
    var colorName: String?

    /// Default length in minutes, applied to the end time when the preset is
    /// picked in the editor. Used only when no fixed schedule is set.
    var defaultDurationMinutes: Int?

    /// A fixed schedule, as minutes after midnight: 540 and 900 mean 09:00 to
    /// 15:00. Both set means the preset pins the times, not just the length.
    var defaultStartMinute: Int?
    var defaultEndMinute: Int?

    var createdAt: Date = Date()

    var subject: Subject?

    @Relationship(deleteRule: .nullify, inverse: \Event.preset)
    var events: [Event]?

    init(
        id: UUID = UUID(),
        name: String = "",
        type: EventType = .work,
        title: String? = nil,
        compensationType: CompensationType? = nil,
        hourlyRateCents: Int? = nil,
        fixedRateCents: Int? = nil,
        schoolKind: SchoolEventKind? = nil,
        address: String? = nil,
        notes: String? = nil,
        colorName: String? = nil,
        defaultDurationMinutes: Int? = nil,
        subject: Subject? = nil
    ) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.title = title
        self.compensationTypeRaw = compensationType?.rawValue
        self.hourlyRateCents = hourlyRateCents
        self.fixedRateCents = fixedRateCents
        self.schoolKindRaw = schoolKind?.rawValue
        self.address = address
        self.notes = notes
        self.colorName = colorName
        self.defaultDurationMinutes = defaultDurationMinutes
        self.createdAt = Date()
        self.subject = subject
    }
}

extension Preset {
    var type: EventType {
        get { EventType(rawValue: typeRaw) ?? .work }
        set { typeRaw = newValue.rawValue }
    }

    var compensationType: CompensationType? {
        get { compensationTypeRaw.flatMap(CompensationType.init(rawValue:)) }
        set { compensationTypeRaw = newValue?.rawValue }
    }

    var schoolKind: SchoolEventKind? {
        get { schoolKindRaw.flatMap(SchoolEventKind.init(rawValue:)) }
        set { schoolKindRaw = newValue?.rawValue }
    }

    /// When the preset puts an entry: fixed times win over a length, and a
    /// preset may carry neither.
    var timing: PresetTiming? {
        if let start = defaultStartMinute, let end = defaultEndMinute {
            return .schedule(start: start, end: end)
        }
        if let minutes = defaultDurationMinutes, minutes > 0 {
            return .length(minutes: minutes)
        }
        return nil
    }

    /// One-line description of what this preset fills in, shown under its name.
    func summary(locale: Locale) -> String {
        [timing?.summary(locale: locale), detailSummary].compactMap { $0 }.joined(separator: " · ")
    }

    private var detailSummary: String {
        switch type {
        case .work:
            switch compensationType {
            case .hourly:
                if let cents = hourlyRateCents {
                    return String(localized: "\(Money.string(cents: cents)) per hour")
                }
                return String(localized: "Hourly")
            case .fixed:
                if let cents = fixedRateCents {
                    return String(localized: "\(Money.string(cents: cents)) fixed")
                }
                return String(localized: "Fixed rate")
            case nil:
                return String(localized: "Work")
            }
        case .school:
            return subject?.name ?? String(localized: "School")
        case .calendar:
            return String(localized: "Calendar")
        }
    }
}

/// When a preset places an entry.
enum PresetTiming: Equatable, Sendable {
    /// Fixed times of day, as minutes after midnight. An end at or before the
    /// start means the shift runs past midnight.
    case schedule(start: Int, end: Int)
    /// Keeps whatever start the user picked and sets the length.
    case length(minutes: Int)

    /// The start and end this timing gives an entry on `day`.
    ///
    /// Days are added with the calendar rather than as 24 hours, so an
    /// overnight shift across a daylight-saving change still ends at the time
    /// on the clock.
    func dates(onDayOf day: Date, currentStart: Date, calendar: Calendar) -> (start: Date, end: Date) {
        switch self {
        case .schedule(let startMinute, let endMinute):
            let midnight = calendar.startOfDay(for: day)
            let start = Self.time(startMinute, on: midnight, calendar: calendar)
            var end = Self.time(endMinute, on: midnight, calendar: calendar)
            if end <= start {
                end = calendar.date(byAdding: .day, value: 1, to: end) ?? end.addingTimeInterval(86_400)
            }
            return (start, end)
        case .length(let minutes):
            return (currentStart, currentStart.addingTimeInterval(TimeInterval(minutes * 60)))
        }
    }

    /// "09:00–15:00" or "7h 45m". Times follow `locale`, which the app pins to
    /// a 24-hour clock.
    func summary(locale: Locale) -> String {
        switch self {
        case .schedule(let start, let end):
            let midnight = Calendar.current.startOfDay(for: Date())
            let style = Date.FormatStyle.dateTime.hour().minute().locale(locale)
            let from = Self.time(start, on: midnight, calendar: .current).formatted(style)
            let to = Self.time(end, on: midnight, calendar: .current).formatted(style)
            return "\(from)–\(to)"
        case .length(let minutes):
            return Self.durationText(minutes: minutes)
        }
    }

    /// "8h", "7h 45m", "45m".
    static func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 && remainder > 0 { return String(localized: "\(hours)h \(remainder)m") }
        if hours > 0 { return String(localized: "\(hours)h") }
        return String(localized: "\(remainder)m")
    }

    static func time(_ minuteOfDay: Int, on midnight: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: midnight) ?? midnight
    }
}
