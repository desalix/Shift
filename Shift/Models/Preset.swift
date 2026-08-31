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
    /// picked in the editor.
    var defaultDurationMinutes: Int?

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

    /// One-line description of what this preset fills in, shown under its name.
    var summary: String {
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
