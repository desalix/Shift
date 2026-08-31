//
//  AssistantAction.swift
//  Shift
//

import Foundation

/// A change the assistant proposes to make.
///
/// The model never writes to the store directly. It emits one of these typed
/// values, the app validates it against the same rules the editor uses, and
/// destructive changes are shown to the user for confirmation before anything
/// is applied. Model output is data, never executable instructions.
enum AssistantAction: Identifiable, Sendable {
    case createEvent(EventSpec)
    case deleteEvent(id: UUID, title: String, date: Date)
    case rescheduleEvent(id: UUID, title: String, newStart: Date, newEnd: Date)
    case createSubject(name: String)
    case enableSchool

    var id: String {
        switch self {
        case .createEvent(let spec):
            "create-\(spec.title)-\(spec.startDate.timeIntervalSinceReferenceDate)"
        case .deleteEvent(let id, _, _):
            "delete-\(id.uuidString)"
        case .rescheduleEvent(let id, _, let newStart, _):
            "move-\(id.uuidString)-\(newStart.timeIntervalSinceReferenceDate)"
        case .createSubject(let name):
            "subject-\(name)"
        case .enableSchool:
            "enable-school"
        }
    }

    /// Deletions and reschedules overwrite existing data, so they always need an
    /// explicit confirmation before being applied.
    var isDestructive: Bool {
        switch self {
        case .deleteEvent, .rescheduleEvent: true
        case .createEvent, .createSubject, .enableSchool: false
        }
    }

    var symbolName: String {
        switch self {
        case .createEvent: "calendar.badge.plus"
        case .deleteEvent: "calendar.badge.minus"
        case .rescheduleEvent: "arrow.left.arrow.right"
        case .createSubject: "book.closed"
        case .enableSchool: "graduationcap"
        }
    }
}

/// The fields needed to create an entry, in a form the model can emit and the
/// app can validate before it becomes an `Event`.
struct EventSpec: Sendable, Hashable {
    var title: String
    var type: EventType
    var startDate: Date
    var endDate: Date
    var address: String?
    var compensationType: CompensationType?
    var hourlyRateCents: Int?
    var fixedRateCents: Int?
    var schoolKind: SchoolEventKind?
    var subjectName: String?
    var notes: String?

    /// Runs the same validation the editor uses. `subject` is resolved by the
    /// caller because only it can look one up in the store.
    func validationErrors(resolvedSubject: Subject?) -> [Event.ValidationError] {
        Event.validate(
            title: title,
            type: type,
            startDate: startDate,
            endDate: endDate,
            compensationType: type == .work ? compensationType : nil,
            hourlyRateCents: type == .work && compensationType == .hourly ? hourlyRateCents : nil,
            fixedRateCents: type == .work && compensationType == .fixed ? fixedRateCents : nil,
            schoolKind: type == .school ? schoolKind : nil,
            subject: type == .school ? resolvedSubject : nil,
            notes: notes
        )
    }
}

/// A batch of proposed actions awaiting the user's decision.
struct AssistantProposal: Identifiable, Sendable {
    let id = UUID()
    var actions: [AssistantAction]

    var containsDestructive: Bool {
        actions.contains { $0.isDestructive }
    }
}
