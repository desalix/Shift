//
//  SubjectsView.swift
//  Shift
//

import SwiftUI
import SwiftData

/// Subject management. Deleting a subject cascades to its events, so it is
/// always confirmed and the confirmation names the number at stake.
struct SubjectsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppErrorReporter.self) private var errorReporter
    @Query(sort: \Subject.name) private var subjects: [Subject]

    @State private var newName = ""
    @State private var pendingDeletion: Subject?
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("New subject", text: $newName)
                        .textInputAutocapitalization(.words)
                        .focused($isNameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit(addSubject)

                    // The button is *absent* rather than disabled while the
                    // field is empty. A disabled button in a List row still
                    // owns the row's tap target, which swallowed the tap meant
                    // for the text field — so the field could never be focused,
                    // so the button could never become enabled. Removing it
                    // leaves the row as a plain text field, which cannot
                    // deadlock the same way.
                    if !trimmedNewName.isEmpty {
                        Button("Add", action: addSubject)
                            .buttonStyle(.borderless)
                    }
                }
                .contentShape(.rect)
                .onTapGesture { isNameFieldFocused = true }
            }

            if subjects.isEmpty {
                Section {
                    Text("No subjects yet. Add the ones you're studying and they'll be available when you create a school entry.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Subjects") {
                    ForEach(subjects) { subject in
                        SubjectRow(subject: subject)
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
        .navigationTitle(Text("Subjects"))
        .navigationBarTitleDisplayMode(.inline)
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

private struct SubjectRow: View {
    @Bindable var subject: Subject

    var body: some View {
        HStack {
            Menu {
                Picker("Colour", selection: Binding(
                    get: { AppColor.named(subject.colorName) },
                    set: { subject.colorName = $0.rawValue }
                )) {
                    ForEach(AppColor.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            } label: {
                Circle()
                    .fill(AppColor.named(subject.colorName).color)
                    .frame(width: 18, height: 18)
            }
            .accessibilityLabel(Text("Subject colour"))

            TextField("Subject", text: $subject.name)

            Spacer(minLength: 8)

            if subject.eventCount > 0 {
                Text("\(subject.eventCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
