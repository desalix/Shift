//
//  Event.swift
//  Shift
//

import Foundation
import SwiftData

/// A single entry on the calendar.
///
/// Every stored property has a default value and every relationship is optional,
/// which is what SwiftData's CloudKit mirroring requires. Enums are persisted as
/// their raw strings so they can be used directly inside `#Predicate`.
@Model
final class Event {
    var id: UUID = UUID()
    var title: String = ""
    var typeRaw: String = EventType.calendar.rawValue
    var startDate: Date = Date()
    var endDate: Date = Date()

    var address: String?

    // Work-only compensation. Exactly one of the two rates is set, matching
    // `compensationType`.
    var compensationTypeRaw: String?
    var hourlyRateCents: Int?
    var fixedRateCents: Int?

    // School-only.
    var schoolKindRaw: String?

    /// Optional, capped at `Event.notesCharacterLimit` by the editor.
    var notes: String?

    /// Overrides the type colour from Settings when set.
    var colorName: String?

    // Simple weekly recurrence. Occurrences are materialised as individual
    // events sharing a `recurrenceID`, so editing or deleting "the series"
    // operates on an explicit group rather than a rule.
    var isRecurring: Bool = false
    var recurrenceID: UUID?
    /// 1 = Sunday … 7 = Saturday, matching `Calendar.component(.weekday:)`.
    var recurringWeekdays: [Int]?
    var recurringEndDate: Date?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var preset: Preset?
    var subject: Subject?

    init(
        id: UUID = UUID(),
        title: String = "",
        type: EventType = .calendar,
        startDate: Date = Date(),
        endDate: Date = Date(),
        address: String? = nil,
        compensationType: CompensationType? = nil,
        hourlyRateCents: Int? = nil,
        fixedRateCents: Int? = nil,
        schoolKind: SchoolEventKind? = nil,
        notes: String? = nil,
        colorName: String? = nil,
        isRecurring: Bool = false,
        recurrenceID: UUID? = nil,
        recurringWeekdays: [Int]? = nil,
        recurringEndDate: Date? = nil,
        preset: Preset? = nil,
        subject: Subject? = nil
    ) {
        self.id = id
        self.title = title
        self.typeRaw = type.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.address = address
        self.compensationTypeRaw = compensationType?.rawValue
        self.hourlyRateCents = hourlyRateCents
        self.fixedRateCents = fixedRateCents
        self.schoolKindRaw = schoolKind?.rawValue
        self.notes = notes
        self.colorName = colorName
        self.isRecurring = isRecurring
        self.recurrenceID = recurrenceID
        self.recurringWeekdays = recurringWeekdays
        self.recurringEndDate = recurringEndDate
        self.createdAt = Date()
        self.updatedAt = Date()
        self.preset = preset
        self.subject = subject
    }
}

// MARK: - Typed accessors

extension Event {
    static let notesCharacterLimit = 250

    var type: EventType {
        get { EventType(rawValue: typeRaw) ?? .calendar }
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

    func touch() { updatedAt = Date() }
}

// MARK: - Derived values

extension Event {
    /// Guards against inverted or zero-length ranges producing negative pay.
    var durationInMinutes: Int {
        max(0, Int(endDate.timeIntervalSince(startDate) / 60.0))
    }

    /// Gross earnings in cents. Non-work events never contribute.
    ///
    /// Hourly pay is computed in integer minute-cents and rounded once at the
    /// end, so a 90-minute shift at €10.00/h yields exactly 1500 rather than a
    /// binary-floating-point approximation of it.
    var earningsInCents: Int {
        guard type == .work else { return 0 }
        switch compensationType {
        case .hourly:
            guard let rate = hourlyRateCents else { return 0 }
            let minuteCents = durationInMinutes * rate
            return Int((Double(minuteCents) / 60.0).rounded())
        case .fixed:
            return fixedRateCents ?? 0
        case nil:
            return 0
        }
    }

    /// True when the event spans more than one calendar day.
    func spansMultipleDays(in calendar: Calendar) -> Bool {
        !calendar.isDate(startDate, inSameDayAs: endDate)
    }
}

// MARK: - Validation

extension Event {
    /// The conditional-requirement rules from the spec: every field is required
    /// except notes, and compensation/school fields are required only when the
    /// selected type makes them applicable.
    enum ValidationError: LocalizedError, Equatable {
        case missingTitle
        case endBeforeStart
        case missingCompensationType
        case missingRate
        case nonPositiveRate
        case missingSchoolKind
        case missingSubject
        case notesTooLong

        var errorDescription: String? {
            switch self {
            case .missingTitle:
                String(localized: "Title is required.")
            case .endBeforeStart:
                String(localized: "The end time must be after the start time.")
            case .missingCompensationType:
                String(localized: "Choose an hourly or a fixed rate.")
            case .missingRate:
                String(localized: "Enter a rate.")
            case .nonPositiveRate:
                String(localized: "The rate must be greater than zero.")
            case .missingSchoolKind:
                String(localized: "Choose exam, assignment, or other.")
            case .missingSubject:
                String(localized: "Choose a subject.")
            case .notesTooLong:
                String(localized: "Notes cannot exceed 250 characters.")
            }
        }
    }

    /// Validates a candidate entry. Kept as a static function over loose values
    /// so the editor can validate a draft before an `Event` is ever inserted,
    /// and so the AI tool layer can validate a proposed mutation the same way.
    static func validate(
        title: String,
        type: EventType,
        startDate: Date,
        endDate: Date,
        compensationType: CompensationType?,
        hourlyRateCents: Int?,
        fixedRateCents: Int?,
        schoolKind: SchoolEventKind?,
        subject: Subject?,
        notes: String?
    ) -> [ValidationError] {
        var errors: [ValidationError] = []

        // Exams take their title from the subject, so an empty title is fine there.
        let titleRequired = !(type == .school && schoolKind == .exam)
        if titleRequired, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingTitle)
        }

        if endDate <= startDate { errors.append(.endBeforeStart) }

        if type == .work {
            switch compensationType {
            case nil:
                errors.append(.missingCompensationType)
            case .hourly:
                if let rate = hourlyRateCents {
                    if rate <= 0 { errors.append(.nonPositiveRate) }
                } else {
                    errors.append(.missingRate)
                }
            case .fixed:
                if let rate = fixedRateCents {
                    if rate <= 0 { errors.append(.nonPositiveRate) }
                } else {
                    errors.append(.missingRate)
                }
            }
        }

        if type == .school {
            if schoolKind == nil { errors.append(.missingSchoolKind) }
            if subject == nil { errors.append(.missingSubject) }
        }

        if let notes, notes.count > notesCharacterLimit { errors.append(.notesTooLong) }

        return errors
    }
}

// MARK: - Presentation

extension Event {
    /// What to show in lists and the month grid.
    ///
    /// Exams have no user-supplied title — the spec says the entry "will just
    /// say exam" — so they are labelled from their subject instead.
    var displayTitle: String {
        if type == .school, schoolKind == .exam {
            if let subjectName = subject?.name, !subjectName.isEmpty {
                return String(localized: "\(subjectName) Exam")
            }
            return String(localized: "Exam")
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Untitled") : trimmed
    }

    /// "09:00 – 14:30", or a date-inclusive range when the event crosses midnight.
    func timeRangeText(calendar: Calendar, locale: Locale = .current) -> String {
        if spansMultipleDays(in: calendar) {
            return "\(startDate.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))) – \(endDate.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale)))"
        }
        return "\(startDate.formatted(.dateTime.hour().minute().locale(locale))) – \(endDate.formatted(.dateTime.hour().minute().locale(locale)))"
    }

    /// "3h 30m", for the detail and income screens.
    var durationText: String {
        let minutes = durationInMinutes
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 && remainder > 0 { return String(localized: "\(hours)h \(remainder)m") }
        if hours > 0 { return String(localized: "\(hours)h") }
        return String(localized: "\(remainder)m")
    }

    /// Short description of the pay arrangement, or nil for non-work entries.
    var rateText: String? {
        guard type == .work else { return nil }
        switch compensationType {
        case .hourly:
            guard let cents = hourlyRateCents else { return nil }
            return String(localized: "\(Money.string(cents: cents))/h")
        case .fixed:
            guard let cents = fixedRateCents else { return nil }
            return String(localized: "\(Money.string(cents: cents)) fixed")
        case nil:
            return nil
        }
    }
}
