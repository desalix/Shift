//
//  Enums.swift
//  Shift
//

import Foundation

/// The three kinds of entry a user can create. `calendar` and `work` are always
/// available; `school` is only surfaced when enabled in Settings.
enum EventType: String, Codable, CaseIterable, Identifiable, Sendable {
    case work
    case school
    case calendar

    var id: String { rawValue }

    /// SF Symbol used for this type throughout the app.
    var symbolName: String {
        switch self {
        case .work: "briefcase.fill"
        case .school: "graduationcap.fill"
        case .calendar: "calendar"
        }
    }
}

/// How a work event pays out. Not applicable to school or calendar events.
enum CompensationType: String, Codable, CaseIterable, Identifiable, Sendable {
    case hourly
    case fixed

    var id: String { rawValue }
}

/// The sub-kind of a school event. `exam` uses a fixed title; the others carry
/// a user-supplied one.
enum SchoolEventKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case exam
    case assignment
    case other

    var id: String { rawValue }

    /// Exams are titled by their subject, so the editor hides the title field.
    var usesCustomTitle: Bool { self != .exam }
}
