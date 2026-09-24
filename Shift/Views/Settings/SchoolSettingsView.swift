//
//  SchoolSettingsView.swift
//  Shift
//

import SwiftUI
import SwiftData

/// The School switch and, while it's on, the subjects.
///
/// Deleting a subject cascades to its entries, so it is always confirmed and
/// the confirmation names the number at stake.
struct SchoolSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(AppErrorReporter.self) private var errorReporter

    @Query(sort: \Subject.name) private var subjects: [Subject]
    @Query(filter: #Predicate<Event> { $0.typeRaw == "school" }) private var schoolEvents: [Event]

    @State private var newName = ""
    @State private var pendingDeletion: Subject?
    @State private var showingDisableWarning = false
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { settings.schoolEnabled },
                    set: { newValue in
                        // Turning School off hides the section but must never
                        // silently discard the user's school data, so warn
                        // only when there is something to lose.
                        if !newValue, hasSchoolData {
                            showingDisableWarning = true
                        } else {
                            settings.schoolEnabled = newValue
                        }
                    }
                )) {
                    Label("School", systemImage: EventType.school.symbolName)
                }
            }

            if settings.schoolEnabled {
                addSubjectSection

                if subjects.isEmpty {
                    Section {
                        Text("No subjects yet. Add the ones you're studying and they'll be available when you create a school entry.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(subjects) { subject in
                            NavigationLink {
                                SubjectEntriesView(subject: subject)
                            } label: {
                                LabeledContent(subject.name) {
                                    if subject.eventCount > 0 {
                                        Text("\(subject.eventCount)")
                                            .monospacedDigit()
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingDeletion = subject
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(Text("School"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(Text("Turn off School?"), isPresented: $showingDisableWarning) {
            Button(String(localized: "Turn Off"), role: .destructive) {
                settings.schoolEnabled = false
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("Your subjects and school entries are kept, but hidden until you turn School back on.")
        }
        .alert(
            Text("Are you sure you want to delete?"),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { subject in
            Button(String(localized: "Delete"), role: .destructive) {
                delete(subject)
            }
            Button(String(localized: "Cancel"), role: .cancel) { pendingDeletion = nil }
        } message: { subject in
            if subject.eventCount > 0 {
                Text("This will delete all linked entries (\(subject.eventCount)).")
            } else {
                Text("This will delete all linked entries.")
            }
        }
    }

    private var addSubjectSection: some View {
        Section {
            HStack {
                TextField("New subject", text: $newName)
                    .textInputAutocapitalization(.words)
                    .focused($isNameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(addSubject)

                // The button is *absent* rather than disabled while the field
                // is empty. A disabled button in a List row still owns the
                // row's tap target, which swallowed the tap meant for the text
                // field — so the field could never be focused, so the button
                // could never become enabled.
                if !trimmedNewName.isEmpty {
                    Button("Add", action: addSubject)
                        .buttonStyle(.borderless)
                }
            }
            .contentShape(.rect)
            .onTapGesture { isNameFieldFocused = true }
        }
    }

    private var hasSchoolData: Bool {
        !subjects.isEmpty || !schoolEvents.isEmpty
    }

    private var trimmedNewName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addSubject() {
        let name = trimmedNewName
        guard !name.isEmpty else { return }
        guard !subjects.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            newName = ""
            return
        }
        modelContext.insert(Subject(name: name))
        modelContext.saveChanges(reporting: errorReporter)
        newName = ""
        // Keep focus so several subjects can be added in a row.
        isNameFieldFocused = true
    }

    /// The cascade rule on `Subject.events` removes the linked entries; deleting
    /// the subject is enough.
    private func delete(_ subject: Subject) {
        modelContext.delete(subject)
        modelContext.saveChanges(reporting: errorReporter)
        pendingDeletion = nil
    }
}

/// Every entry of one subject, in date order. Tap the title to rename it.
struct SubjectEntriesView: View {
    @Bindable var subject: Subject

    var body: some View {
        let entries = (subject.events ?? []).sorted { $0.startDate < $1.startDate }

        List {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("No entries", systemImage: EventType.school.symbolName)
                } description: {
                    Text("School entries for this subject will appear here.")
                }
            } else {
                Section {
                    ForEach(entries) { event in
                        NavigationLink {
                            EventDetailView(event: event)
                        } label: {
                            SubjectEntryRow(event: event)
                        }
                    }
                }
            }
        }
        // A title bound to the name is renamed from the title's own menu,
        // which replaces the name field the list row used to have.
        .navigationTitle($subject.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
    }
}

/// Date first, since a subject's entries span the whole term.
private struct SubjectEntryRow: View {
    let event: Event

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(event.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if event.isRecurring { RecurrenceBadge() }
            }

            Text(verbatim: "\(event.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().locale(locale))) · \(event.timeRangeText(calendar: calendar, locale: locale))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
