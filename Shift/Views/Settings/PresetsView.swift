//
//  PresetsView.swift
//  Shift
//

import SwiftUI
import SwiftData

/// List and manage saved entry templates.
struct PresetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppErrorReporter.self) private var errorReporter
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Preset.name) private var presets: [Preset]

    @State private var editing: Preset?
    @State private var isCreating = false

    var body: some View {
        List {
            if presets.isEmpty {
                Section {
                    Text("No presets yet. Create one for a shift you work often — name it, set the rate, and it'll be one tap when you add the entry.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(presets) { preset in
                    Button {
                        editing = preset
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: preset.type.symbolName)
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(
                                    AppColor.named(preset.colorName ?? settings.color(for: preset.type).rawValue).color,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).foregroundStyle(.primary)
                                Text(preset.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle(Text("Presets"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("New preset"))
            }
        }
        .sheet(isPresented: $isCreating) {
            PresetEditorView(preset: nil)
        }
        .sheet(item: $editing) { preset in
            PresetEditorView(preset: preset)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            // The nullify rule on Preset.events means the entries created from
            // this preset survive; they just lose the back-reference.
            modelContext.delete(presets[index])
        }
        modelContext.saveChanges(reporting: errorReporter)
    }
}

/// Create or edit a preset.
struct PresetEditorView: View {
    let preset: Preset?

    @Environment(\.modelContext) private var modelContext
    @Environment(AppErrorReporter.self) private var errorReporter
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Subject.name) private var subjects: [Subject]

    @State private var name = ""
    @State private var type: EventType = .work
    @State private var title = ""
    @State private var compensationType: CompensationType = .hourly
    @State private var rateText = ""
    @State private var schoolKind: SchoolEventKind = .exam
    @State private var subjectID: UUID?
    @State private var address = ""
    @State private var notes = ""
    @State private var colorName: String?
    @State private var durationMinutes = 60
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Preset") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    Picker("Type", selection: $type) {
                        ForEach(settings.availableEventTypes) { option in
                            Text(typeName(option)).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Defaults") {
                    TextField("Default title", text: $title)
                        .textInputAutocapitalization(.sentences)

                    Stepper(value: $durationMinutes, in: 15 ... 1440, step: 15) {
                        LabeledContent(String(localized: "Length"), value: durationText)
                    }
                }

                if type == .work {
                    Section("Pay") {
                        Picker("Rate type", selection: $compensationType) {
                            Text("Hourly").tag(CompensationType.hourly)
                            Text("Fixed").tag(CompensationType.fixed)
                        }
                        .pickerStyle(.segmented)

                        HStack {
                            Text(compensationType == .hourly
                                 ? String(localized: "Hourly rate")
                                 : String(localized: "Fixed amount"))
                            Spacer()
                            TextField("0.00", text: $rateText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 120)
                            Text(Money.currencySymbol).foregroundStyle(.secondary)
                        }
                    }
                }

                if type == .school {
                    Section("School") {
                        Picker("Kind", selection: $schoolKind) {
                            Text("Exam").tag(SchoolEventKind.exam)
                            Text("Assignment").tag(SchoolEventKind.assignment)
                            Text("Other").tag(SchoolEventKind.other)
                        }
                        .pickerStyle(.segmented)

                        Picker("Subject", selection: $subjectID) {
                            Text("None").tag(UUID?.none)
                            ForEach(subjects) { subject in
                                Text(subject.name).tag(UUID?.some(subject.id))
                            }
                        }
                    }
                }

                if type != .school {
                    Section("Address") {
                        TextField("Optional address", text: $address, axis: .vertical)
                            .lineLimit(1 ... 3)
                    }
                }

                Section("Colour") {
                    Picker("Colour", selection: $colorName) {
                        Text("Default").tag(String?.none)
                        ForEach(AppColor.allCases) { option in
                            Text(option.displayName).tag(String?.some(option.rawValue))
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2 ... 5)
                        .onChange(of: notes) { _, newValue in
                            if newValue.count > Event.notesCharacterLimit {
                                notes = String(newValue.prefix(Event.notesCharacterLimit))
                            }
                        }
                }
            }
            .navigationTitle(preset == nil ? Text("New Preset") : Text("Edit Preset"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    private var durationText: String {
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60
        if hours > 0 && minutes > 0 { return String(localized: "\(hours)h \(minutes)m") }
        if hours > 0 { return String(localized: "\(hours)h") }
        return String(localized: "\(minutes)m")
    }

    private func typeName(_ type: EventType) -> String {
        switch type {
        case .work: String(localized: "Work")
        case .school: String(localized: "School")
        case .calendar: String(localized: "Calendar")
        }
    }

    private func loadIfNeeded() {
        guard !didLoad, let preset else { didLoad = true; return }
        didLoad = true
        name = preset.name
        type = preset.type
        title = preset.title ?? ""
        compensationType = preset.compensationType ?? .hourly
        switch preset.compensationType {
        case .hourly: rateText = preset.hourlyRateCents.map { Money.editableString(cents: $0) } ?? ""
        case .fixed: rateText = preset.fixedRateCents.map { Money.editableString(cents: $0) } ?? ""
        case nil: rateText = ""
        }
        schoolKind = preset.schoolKind ?? .exam
        subjectID = preset.subject?.id
        address = preset.address ?? ""
        notes = preset.notes ?? ""
        colorName = preset.colorName
        durationMinutes = preset.defaultDurationMinutes ?? 60
    }

    private func save() {
        let target = preset ?? Preset()
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.type = type
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.title = trimmedTitle.isEmpty ? nil : trimmedTitle
        target.defaultDurationMinutes = durationMinutes
        target.colorName = colorName
        target.notes = notes.isEmpty ? nil : notes

        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        target.address = (type != .school && !trimmedAddress.isEmpty) ? trimmedAddress : nil

        if type == .work {
            target.compensationType = compensationType
            let cents = Money.cents(from: rateText)
            target.hourlyRateCents = compensationType == .hourly ? cents : nil
            target.fixedRateCents = compensationType == .fixed ? cents : nil
        } else {
            target.compensationType = nil
            target.hourlyRateCents = nil
            target.fixedRateCents = nil
        }

        if type == .school {
            target.schoolKind = schoolKind
            target.subject = subjectID.flatMap { id in subjects.first { $0.id == id } }
        } else {
            target.schoolKind = nil
            target.subject = nil
        }

        if preset == nil { modelContext.insert(target) }
        modelContext.saveChanges(reporting: errorReporter)
        dismiss()
    }
}
