//
//  DayEventsView.swift
//  Shift
//

import SwiftUI
import SwiftData

/// The scrollable list of everything on one day, reached by tapping a day box
/// (or its "+N More" line).
struct DayEventsView: View {
    let day: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppErrorReporter.self) private var errorReporter
    @Environment(\.calendar) private var calendar
    @Environment(AppSettings.self) private var settings

    @Query private var events: [Event]

    @State private var editorMode: EventEditorView.Mode?
    @State private var pendingDeletion: Event?
    @State private var pendingDeletionHasSiblings = false

    init(day: Date) {
        self.day = day
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
        NavigationStack {
            Group {
                if events.isEmpty {
                    ContentUnavailableView {
                        Label("No entries", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text("Nothing scheduled for this day.")
                    } actions: {
                        Button("Add Entry") {
                            editorMode = .create(initialDate: day)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(events) { event in
                            NavigationLink {
                                EventDetailView(event: event)
                            } label: {
                                EventRow(event: event)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    // Resolve membership before prompting so a
                                    // one-off entry isn't asked to choose
                                    // between two identical outcomes.
                                    pendingDeletionHasSiblings = EventSeries.hasSiblings(event, context: modelContext)
                                    pendingDeletion = event
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorMode = .create(initialDate: day)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("New entry"))
                }
            }
            .sheet(item: $editorMode) { mode in
                EventEditorView(mode: mode)
            }
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
    }

    private func delete(_ event: Event, scope: EventSeries.Scope) {
        EventSeries.delete(event, scope: scope, context: modelContext)
        modelContext.saveChanges(reporting: errorReporter, while: String(localized: "Deleting"))
        pendingDeletion = nil
    }
}

/// One line in a day list: title, time range, and the type/rate context that
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

            if event.type == .work, event.earningsInCents > 0 {
                Text(Money.string(cents: event.earningsInCents, locale: locale))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
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
            event.address
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
