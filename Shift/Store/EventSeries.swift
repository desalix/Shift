//
//  EventSeries.swift
//  Shift
//

import Foundation
import SwiftData

/// Operations that act on a whole recurrence group.
///
/// Weekly repeats are stored as individual events sharing a `recurrenceID`
/// rather than as a rule, so "the series" is an explicit set of rows. This is
/// the one place that knows how to gather and mutate that set, so the day list,
/// the detail screen, and the editor cannot drift apart on what "all in series"
/// means.
enum EventSeries {

    /// Whether this entry is part of a group with more than one occurrence.
    ///
    /// A one-occurrence group is not worth prompting about — it would ask the
    /// user to choose between two identical outcomes.
    @MainActor
    static func hasSiblings(_ event: Event, context: ModelContext) -> Bool {
        siblings(of: event, context: context).count > 1
    }

    /// Every event in the same recurrence group, including `event` itself.
    /// Returns just `event` when it does not belong to one.
    @MainActor
    static func siblings(of event: Event, context: ModelContext) -> [Event] {
        guard event.isRecurring, let recurrenceID = event.recurrenceID else { return [event] }
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate<Event> { $0.recurrenceID == recurrenceID },
            sortBy: [SortDescriptor(\Event.startDate)]
        )
        guard let found = try? context.fetch(descriptor), !found.isEmpty else { return [event] }
        return found
    }

    @MainActor
    static func delete(_ event: Event, scope: Scope, context: ModelContext) {
        switch scope {
        case .thisOccurrence:
            context.delete(event)
        case .wholeSeries:
            for sibling in siblings(of: event, context: context) {
                context.delete(sibling)
            }
        }
    }

    /// Which occurrences an edit or deletion applies to.
    enum Scope {
        case thisOccurrence
        case wholeSeries
    }

    /// Copies the edited entry's details onto its siblings, keeping each
    /// occurrence on its own date.
    ///
    /// Time of day and duration propagate — moving a series from 14:30 to 15:00
    /// is the common reason to edit one at all — but the calendar day of each
    /// occurrence is left alone, since that is what makes them a series.
    @MainActor
    static func propagate(from edited: Event, context: ModelContext, calendar: Calendar) {
        let duration = edited.endDate.timeIntervalSince(edited.startDate)
        let time = calendar.dateComponents([.hour, .minute, .second], from: edited.startDate)

        for sibling in siblings(of: edited, context: context) where sibling !== edited {
            sibling.title = edited.title
            sibling.type = edited.type
            sibling.address = edited.address
            sibling.compensationType = edited.compensationType
            sibling.hourlyRateCents = edited.hourlyRateCents
            sibling.fixedRateCents = edited.fixedRateCents
            sibling.schoolKind = edited.schoolKind
            sibling.subject = edited.subject
            sibling.notes = edited.notes
            sibling.colorName = edited.colorName
            sibling.preset = edited.preset

            if let newStart = calendar.date(
                bySettingHour: time.hour ?? 0,
                minute: time.minute ?? 0,
                second: time.second ?? 0,
                of: sibling.startDate
            ) {
                sibling.startDate = newStart
                sibling.endDate = newStart.addingTimeInterval(duration)
            }

            sibling.touch()
        }
    }
}
