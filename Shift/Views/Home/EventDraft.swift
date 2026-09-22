//
//  EventDraft.swift
//  Shift
//

import Foundation
import SwiftUI

extension EventEditorView {
    /// A plain value holding the in-progress form.
    ///
    /// The editor works on this rather than binding straight to a live `Event`
    /// so that cancelling genuinely discards changes — binding to the model
    /// object would write every keystroke into the store immediately.
    struct Draft {
        var type: EventType = .calendar
        var title: String = ""
        var startDate: Date = Date()
        var endDate: Date = Date().addingTimeInterval(3600)

        /// Whether this shift records money at all. Off means the entry is a
        /// record of time — the fixed-monthly-wage case.
        var tracksPay: Bool = true
        var compensationType: CompensationType = .hourly
        /// Held as text so partially-typed input ("12.") isn't destroyed by
        /// round-tripping through a number on every keystroke.
        var rateText: String = ""

        var schoolKind: SchoolEventKind = .exam
        var subjectID: UUID?
        var presetID: UUID?

        var notes: String = ""
        var colorName: String?

        var isRecurring: Bool = false
        var recurringWeekdays: Set<Int> = []
        var recurringEndDate: Date = Date().addingTimeInterval(60 * 60 * 24 * 30)

        init() {}

        /// A fresh entry, snapped to the next whole hour on the chosen day.
        init(initialDate: Date, calendar: Calendar, defaultType: EventType, tracksPay: Bool = true) {
            type = defaultType
            self.tracksPay = tracksPay

            let now = Date()
            let hour: Int
            if calendar.isDate(initialDate, inSameDayAs: now) {
                hour = min(23, calendar.component(.hour, from: now) + 1)
            } else {
                hour = 9
            }

            let start = calendar.date(
                bySettingHour: hour, minute: 0, second: 0, of: initialDate
            ) ?? initialDate

            startDate = start
            endDate = start.addingTimeInterval(3600)
            recurringEndDate = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            recurringWeekdays = [calendar.component(.weekday, from: start)]
        }

        init(event: Event) {
            type = event.type
            title = event.title
            startDate = event.startDate
            endDate = event.endDate
            // A stored compensation type is the record of pay being tracked.
            tracksPay = event.compensationType != nil
            compensationType = event.compensationType ?? .hourly
            switch event.compensationType {
            case .hourly:
                rateText = event.hourlyRateCents.map { Money.editableString(cents: $0) } ?? ""
            case .fixed:
                rateText = event.fixedRateCents.map { Money.editableString(cents: $0) } ?? ""
            case nil:
                rateText = ""
            }
            schoolKind = event.schoolKind ?? .exam
            subjectID = event.subject?.id
            presetID = event.preset?.id
            notes = event.notes ?? ""
            colorName = event.colorName
            isRecurring = event.isRecurring
            recurringWeekdays = Set(event.recurringWeekdays ?? [])
            recurringEndDate = event.recurringEndDate ?? event.startDate
        }

        /// Clears fields that don't apply after a type change, so a rate typed
        /// under Work can't leak onto a Calendar entry.
        mutating func applyTypeDefaults(_ newType: EventType) {
            presetID = nil
            if newType == .calendar {
                rateText = ""
            }
        }

        mutating func apply(preset: Preset, calendar: Calendar) {
            type = preset.type
            if let presetTitle = preset.title, !presetTitle.isEmpty { title = presetTitle }
            if let presetNotes = preset.notes { notes = String(presetNotes.prefix(Event.notesCharacterLimit)) }
            if let color = preset.colorName { colorName = color }

            if preset.type == .work {
                // A work preset states whether its shift is paid: saved with pay
                // it switches Track pay on, saved without it switches it off.
                tracksPay = preset.compensationType != nil
                if let compensation = preset.compensationType {
                    compensationType = compensation
                    switch compensation {
                    case .hourly:
                        if let cents = preset.hourlyRateCents { rateText = Money.editableString(cents: cents) }
                    case .fixed:
                        if let cents = preset.fixedRateCents { rateText = Money.editableString(cents: cents) }
                    }
                }
            }

            if preset.type == .school {
                if let kind = preset.schoolKind { schoolKind = kind }
                if let subject = preset.subject { subjectID = subject.id }
            }

            if let timing = preset.timing {
                // A schedule pins the times on the day already chosen; a length
                // keeps the chosen start.
                let dates = timing.dates(onDayOf: startDate, currentStart: startDate, calendar: calendar)
                startDate = dates.start
                endDate = dates.end
            }
        }

        /// Copies the draft onto a model object. Fields that don't apply to the
        /// selected type are explicitly nilled rather than left stale.
        func write(into event: Event, subject: Subject?, preset: Preset?) {
            event.type = type
            event.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            event.startDate = startDate
            event.endDate = endDate
            event.colorName = colorName
            event.notes = notes.isEmpty ? nil : notes
            event.preset = preset

            // `address` is left alone: the field was removed in 1.1, and an
            // address saved in 1.0 should survive an edit rather than vanish.

            if type == .work, tracksPay {
                event.compensationType = compensationType
                let cents = Money.cents(from: rateText)
                event.hourlyRateCents = compensationType == .hourly ? cents : nil
                event.fixedRateCents = compensationType == .fixed ? cents : nil
            } else {
                // No compensation type is how an untracked-pay shift is stored.
                event.compensationType = nil
                event.hourlyRateCents = nil
                event.fixedRateCents = nil
            }

            if type == .school {
                event.schoolKind = schoolKind
                event.subject = subject
            } else {
                event.schoolKind = nil
                event.subject = nil
            }

            event.isRecurring = isRecurring
            if isRecurring {
                event.recurringWeekdays = Array(recurringWeekdays).sorted()
                event.recurringEndDate = recurringEndDate
            } else {
                event.recurringWeekdays = nil
                event.recurringEndDate = nil
                event.recurrenceID = nil
            }

            event.touch()
        }
    }
}

/// Circular weekday toggles for the weekly repeat rule.
struct WeekdaySelector: View {
    @Binding var selection: Set<Int>
    let calendar: Calendar
    let locale: Locale

    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 6) {
            ForEach(orderedWeekdays, id: \.index) { weekday in
                let isOn = selection.contains(weekday.index)
                Button {
                    if isOn { selection.remove(weekday.index) } else { selection.insert(weekday.index) }
                } label: {
                    Text(weekday.symbol)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            Circle()
                                .fill(isOn ? settings.accentColor.color : Color(.tertiarySystemFill))
                        }
                        .foregroundStyle(isOn ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(weekday.symbol))
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.vertical, 4)
    }

    /// Weekday indexes rotated to begin at the locale's first weekday, paired
    /// with their localised one-letter symbol.
    private var orderedWeekdays: [(index: Int, symbol: String)] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]

        return (0 ..< 7).compactMap { offset in
            let index = ((calendar.firstWeekday - 1 + offset) % 7) + 1
            guard index - 1 < symbols.count else { return nil }
            return (index, symbols[index - 1])
        }
    }
}
