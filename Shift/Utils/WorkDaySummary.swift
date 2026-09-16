//
//  WorkDaySummary.swift
//  Shift
//

import Foundation

/// Splits a day's entries into the work that defines the day and everything
/// else that merely happens during it.
///
/// Work drives the whole day box in the month grid — its colour, and a headline
/// under the day number — while school and calendar entries stay as chips
/// underneath. Keeping the rule here rather than in the view means the headline
/// can be tested without rendering anything.
struct WorkDaySummary {
    let workEvents: [Event]
    let otherEvents: [Event]

    init(events: [Event]) {
        workEvents = events.filter { $0.type == .work }
        otherEvents = events.filter { $0.type != .work }
    }

    var isWorkDay: Bool { !workEvents.isEmpty }

    /// The bold line under the day number: the shift's own title when there is
    /// one, a count when there are several — two titles in a box this small
    /// would truncate to noise — and nothing at all on a day without work.
    var headline: String? {
        switch workEvents.count {
        case 0:
            nil
        case 1:
            workEvents[0].displayTitle
        default:
            // Plain plural, not inflection markup: this branch only runs for two
            // or more, so the plural is unconditional — and the `^[…](inflect:)`
            // form rendered literally as "^[2 shift…" in the grid.
            String(localized: "\(workEvents.count) shifts")
        }
    }

    /// The colour the day box is tinted with, taken from the first shift so a
    /// per-entry colour override still wins over the type colour.
    var leadEvent: Event? { workEvents.first }

    /// Only meaningful for a single shift; a count headline has no one entry to
    /// attach a recurrence marker to.
    var showsRecurrenceMarker: Bool {
        workEvents.count == 1 && workEvents[0].isRecurring
    }
}
