//
//  EventDetailView.swift
//  Shift
//

import SwiftUI
import SwiftData

/// Full detail for a single entry: title, times, address, rate, and notes.
struct EventDetailView: View {
    @Bindable var event: Event

    @Environment(\.modelContext) private var modelContext
    @Environment(AppErrorReporter.self) private var errorReporter
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @State private var isPresentingEditor = false
    @State private var deleteRequest: DeleteRequest?

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: event.type.symbolName)
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(settings.color(for: event), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.displayTitle)
                            .font(.title3.weight(.semibold))
                        Text(typeDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    if event.isRecurring { RecurrenceBadge() }
                }
                .padding(.vertical, 6)
            }

            Section("When") {
                DetailRow(label: String(localized: "Starts"), value: event.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().hour().minute().locale(locale)))
                DetailRow(label: String(localized: "Ends"), value: event.endDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().hour().minute().locale(locale)))
                DetailRow(label: String(localized: "Duration"), value: event.durationText)

                if event.isRecurring, let weekdays = event.recurringWeekdays, let until = event.recurringEndDate {
                    DetailRow(
                        label: String(localized: "Repeats"),
                        value: Recurrence.description(weekdays: weekdays, until: until, calendar: calendar, locale: locale)
                    )
                }
            }

            if event.type == .work, event.compensationType != nil {
                Section("Pay") {
                    if let rate = event.rateText {
                        DetailRow(label: String(localized: "Rate"), value: rate)
                    }
                    DetailRow(
                        label: String(localized: "Earnings"),
                        value: Money.string(cents: event.earningsInCents, locale: locale),
                        emphasized: true
                    )
                }
            }

            if event.type == .school {
                Section("School") {
                    if let kind = event.schoolKind {
                        DetailRow(label: String(localized: "Kind"), value: kindName(kind))
                    }
                    if let subject = event.subject {
                        DetailRow(label: String(localized: "Subject"), value: subject.name)
                    }
                }
            }

            if let address = event.address, !address.isEmpty {
                Section("Address") {
                    Text(address)
                        .textSelection(.enabled)
                }
            }

            if let notes = event.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .textSelection(.enabled)
                }
            }

            if let preset = event.preset {
                Section {
                    DetailRow(label: String(localized: "Created from"), value: preset.name)
                }
            }

            Section {
                Button(role: .destructive) {
                    // Same test the day list uses, so both screens agree on
                    // when "all in series" is a meaningful choice.
                    deleteRequest = EventSeries.hasSiblings(event, context: modelContext)
                        ? .askScope
                        : .single
                } label: {
                    Label("Delete Entry", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .navigationTitle(Text("Details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isPresentingEditor = true }
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            EventEditorView(mode: .edit(event))
        }
        .confirmationDialog(
            Text("Delete this entry?"),
            isPresented: Binding(
                get: { deleteRequest != nil },
                set: { if !$0 { deleteRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            if deleteRequest == .askScope {
                Button(String(localized: "Delete This Entry Only"), role: .destructive) {
                    deleteSingle()
                }
                Button(String(localized: "Delete All in Series"), role: .destructive) {
                    deleteSeries()
                }
            } else {
                Button(String(localized: "Delete"), role: .destructive) {
                    deleteSingle()
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) { deleteRequest = nil }
        } message: {
            if deleteRequest == .askScope {
                Text("This entry repeats. You can delete just this occurrence or the whole series.")
            }
        }
    }

    private enum DeleteRequest: Identifiable {
        case single, askScope
        var id: Int { self == .single ? 0 : 1 }
    }

    private var typeDescription: String {
        switch event.type {
        case .work: String(localized: "Work")
        case .school: String(localized: "School")
        case .calendar: String(localized: "Calendar")
        }
    }

    private func kindName(_ kind: SchoolEventKind) -> String {
        switch kind {
        case .exam: String(localized: "Exam")
        case .assignment: String(localized: "Assignment")
        case .other: String(localized: "Other")
        }
    }

    private func deleteSingle() { delete(scope: .thisOccurrence) }

    private func deleteSeries() { delete(scope: .wholeSeries) }

    private func delete(scope: EventSeries.Scope) {
        EventSeries.delete(event, scope: scope, context: modelContext)
        guard modelContext.saveChanges(reporting: errorReporter, while: String(localized: "Deleting")) else { return }
        dismiss()
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var emphasized: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .fontWeight(emphasized ? .semibold : .regular)
        }
    }
}
