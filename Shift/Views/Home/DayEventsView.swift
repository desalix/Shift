//
//  DayEventsView.swift
//  Shift
//

import SwiftUI
import SwiftData

/// Everything on one day, reached by tapping a day box (or its "+N More" line).
/// Days sit side by side, so a horizontal drag pulls the next or previous day
/// in under the finger.
///
/// Work comes first and is always on screen — even an empty day shows the block,
/// offering to start a shift — because whether the day was worked is the
/// question this app exists to answer.
struct DayEventsView: View {
    /// The day that was tapped. Pages are counted in days from it.
    private let firstDay: Date
    @State private var offset = 0
    @State private var editorMode: EventEditorView.Mode?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar

    /// Ten years either way — far past anything anyone will swipe through.
    private static let reach = 3653

    init(day: Date) {
        firstDay = day
    }

    var body: some View {
        NavigationStack {
            Pager(range: -Self.reach ..< Self.reach + 1, index: $offset) { pageOffset in
                DayEventsList(day: day(at: pageOffset)) { type in
                    editorMode = .create(initialDate: day(at: pageOffset), type: type)
                }
            }
            .navigationTitle(day(at: offset).formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            // Out here rather than on each page, so there's one + for the
            // day on screen.
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorMode = .create(initialDate: day(at: offset), type: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("New entry"))
                }
            }
            .sheet(item: $editorMode) { mode in
                EventEditorView(mode: mode)
            }
        }
    }

    private func day(at offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: firstDay) ?? firstDay
    }
}

/// One day's entries. Horizontal drags turn the day, so deleting is in each
/// row's long-press menu rather than a swipe action — and in the entry's
/// detail screen, as before.
private struct DayEventsList: View {
    let day: Date
    let add: (EventType?) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AppErrorReporter.self) private var errorReporter
    @Environment(AppSettings.self) private var settings

    @Query private var events: [Event]

    @State private var pendingDeletion: Event?
    @State private var pendingDeletionHasSiblings = false

    init(day: Date, add: @escaping (EventType?) -> Void) {
        self.day = day
        self.add = add
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = .autoupdatingCurrent
        let bounds = CalendarMath.dayBounds(for: day, calendar: calendar)
        let start = bounds.start
        let end = bounds.end
        _events = Query(
            filter: #Predicate<Event> { event in
                event.startDate < end && event.endDate >= start
            },
            sort: [SortDescriptor(\Event.startDate), SortDescriptor(\Event.title)]
        )
    }

    var body: some View {
        let summary = WorkDaySummary(events: events.filter(settings.shows))

        List {
            Section("Work") {
                if summary.workEvents.isEmpty {
                    Button {
                        add(.work)
                    } label: {
                        Label("Add work day", systemImage: "plus.circle.fill")
                    }
                } else {
                    ForEach(summary.workEvents) { event in
                        NavigationLink {
                            EventDetailView(event: event)
                        } label: {
                            WorkSummaryRow(event: event)
                        }
                        .contextMenu {
                            deleteButton(for: event)
                        }
                    }
                }
            }

            if !summary.otherEvents.isEmpty {
                Section("Other entries") {
                    ForEach(summary.otherEvents) { event in
                        NavigationLink {
                            EventDetailView(event: event)
                        } label: {
                            EventRow(event: event)
                        }
                        .contextMenu {
                            deleteButton(for: event)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .confirmationDialog(
            Text("Delete this entry?"),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { event in
            if pendingDeletionHasSiblings {
                Button(String(localized: "Delete This Entry Only"), role: .destructive) {
                    delete(event, scope: .thisOccurrence)
                }
                Button(String(localized: "Delete All in Series"), role: .destructive) {
                    delete(event, scope: .wholeSeries)
                }
            } else {
                Button(String(localized: "Delete"), role: .destructive) {
                    delete(event, scope: .thisOccurrence)
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) { pendingDeletion = nil }
        } message: { _ in
            if pendingDeletionHasSiblings {
                Text("This entry repeats. You can delete just this occurrence or the whole series.")
            }
        }
    }

    private func deleteButton(for event: Event) -> some View {
        Button(role: .destructive) {
            // Resolve membership before prompting so a one-off entry isn't
            // asked to choose between two identical outcomes.
            pendingDeletionHasSiblings = EventSeries.hasSiblings(event, context: modelContext)
            pendingDeletion = event
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func delete(_ event: Event, scope: EventSeries.Scope) {
        EventSeries.delete(event, scope: scope, context: modelContext)
        modelContext.saveChanges(reporting: errorReporter, while: String(localized: "Deleting"))
        pendingDeletion = nil
    }
}

/// A shift in the day's Work block: when it ran, what it pays, what it earned.
/// With pay untracked it shows the times alone rather than an empty €0.
struct WorkSummaryRow: View {
    let event: Event

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(event.displayTitle)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                if event.isRecurring { RecurrenceBadge() }

                Spacer(minLength: 0)

                if event.earningsInCents > 0 {
                    Text(Money.string(cents: event.earningsInCents, locale: locale))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                }
            }

            HStack(spacing: 6) {
                Text(event.timeRangeText(calendar: calendar, locale: locale))
                Text(verbatim: "·")
                Text(event.durationText)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let rate = event.rateText {
                Text(rate)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// One line in a day list: title, time range, and the type context that
/// distinguishes two same-titled entries at a glance.
struct EventRow: View {
    let event: Event

    @Environment(AppSettings.self) private var settings
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(settings.color(for: event))
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.displayTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if event.isRecurring {
                        RecurrenceBadge()
                    }
                }

                Text(event.timeRangeText(calendar: calendar, locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let context = secondaryContext {
                    Text(context)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var secondaryContext: String? {
        switch event.type {
        case .work:
            event.rateText
        case .school:
            event.subject?.name
        case .calendar:
            nil
        }
    }
}

/// The "Rec" marker from the spec, used wherever there is room for text.
struct RecurrenceBadge: View {
    var body: some View {
        Text("Rec")
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.18), in: Capsule())
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Recurring"))
    }
}
