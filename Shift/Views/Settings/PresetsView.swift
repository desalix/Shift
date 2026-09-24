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
    @Environment(\.locale) private var locale
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
                                Text(preset.summary(locale: locale))
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
    @Environment(\.calendar) private var calendar
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Subject.name) private var subjects: [Subject]

    /// `none` is a preset that leaves the entry's times alone.
    private enum TimingMode: Hashable { case schedule, length, none }

    @State private var name = ""
    @State private var type: EventType = .work
    @State private var title = ""
    @State private var timingMode: TimingMode = .schedule
    @State private var scheduleStart = PresetEditorView.today(atMinute: 9 * 60)
    @State private var scheduleEnd = PresetEditorView.today(atMinute: 17 * 60)
    @State private var durationMinutes = 8 * 60
    @State private var tracksPay = true
    @State private var compensationType: CompensationType = .hourly
    @State private var rateText = ""
    @State private var schoolKind: SchoolEventKind = .exam
    @State private var subjectID: UUID?
    @State private var notes = ""
    @State private var colorName: String?
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

                Section("Title") {
                    TextField("Default title", text: $title)
                        .textInputAutocapitalization(.sentences)
                }

                timingSection

                if type == .work {
                    PayFields(
                        tracksPay: $tracksPay,
                        compensationType: $compensationType,
                        rateText: $rateText,
                        durationMinutes: timingMinutes
                    )
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
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    // MARK: - Timing

    /// Fixed times of day, just a length, or neither — switched the same way
    /// as Hourly and Fixed pay.
    private var timingSection: some View {
        Section {
            Picker("When", selection: $timingMode) {
                Text("Schedule").tag(TimingMode.schedule)
                Text("Length").tag(TimingMode.length)
                Text("Any time").tag(TimingMode.none)
            }
            .pickerStyle(.segmented)

            switch timingMode {
            case .schedule:
                DatePicker("Starts", selection: $scheduleStart, displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: $scheduleEnd, displayedComponents: .hourAndMinute)
            case .length:
                DurationWheel(minutes: $durationMinutes)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
            case .none:
                EmptyView()
            }
        } header: {
            Text("When")
        } footer: {
            switch timingMode {
            case .schedule:
                if endsNextDay {
                    Text("Ends next day")
                } else if let minutes = timingMinutes {
                    Text(PresetTiming.durationText(minutes: minutes))
                }
            case .length:
                EmptyView()
            case .none:
                Text("The entry keeps the time you choose.")
            }
        }
    }

    private var startMinute: Int { minuteOfDay(scheduleStart) }
    private var endMinute: Int { minuteOfDay(scheduleEnd) }
    private var endsNextDay: Bool { endMinute <= startMinute }

    /// The length the chosen timing gives a shift, for the footer and the
    /// estimated earnings. Nil when the preset sets no times.
    private var timingMinutes: Int? {
        switch timingMode {
        case .schedule: endsNextDay ? endMinute + 1440 - startMinute : endMinute - startMinute
        case .length: durationMinutes
        case .none: nil
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !(timingMode == .length && durationMinutes == 0)
    }

    private func minuteOfDay(_ date: Date) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    private static func today(atMinute minute: Int) -> Date {
        PresetTiming.time(minute, on: Calendar.current.startOfDay(for: Date()), calendar: .current)
    }

    private func typeName(_ type: EventType) -> String {
        switch type {
        case .work: String(localized: "Work")
        case .school: String(localized: "School")
        case .calendar: String(localized: "Calendar")
        }
    }

    // MARK: - Load and save

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        guard let preset else {
            // A new preset starts from whatever the last work entry or preset
            // chose, the same default the entry editor uses.
            tracksPay = settings.tracksPayByDefault
            return
        }

        name = preset.name
        type = preset.type
        title = preset.title ?? ""

        switch preset.timing {
        case .schedule(let start, let end):
            timingMode = .schedule
            scheduleStart = Self.today(atMinute: start)
            scheduleEnd = Self.today(atMinute: end)
        case .length(let minutes):
            timingMode = .length
            durationMinutes = minutes
        case nil:
            // Saved without times. Opening it must not quietly pin the
            // 09:00–17:00 default on the next save.
            timingMode = .none
        }

        tracksPay = preset.compensationType != nil
        compensationType = preset.compensationType ?? .hourly
        switch preset.compensationType {
        case .hourly: rateText = preset.hourlyRateCents.map { Money.editableString(cents: $0) } ?? ""
        case .fixed: rateText = preset.fixedRateCents.map { Money.editableString(cents: $0) } ?? ""
        case nil: rateText = ""
        }

        schoolKind = preset.schoolKind ?? .exam
        subjectID = preset.subject?.id
        notes = preset.notes ?? ""
        colorName = preset.colorName
    }

    private func save() {
        let target = preset ?? Preset()
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.type = type
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.title = trimmedTitle.isEmpty ? nil : trimmedTitle
        target.colorName = colorName
        target.notes = notes.isEmpty ? nil : notes

        switch timingMode {
        case .schedule:
            target.defaultStartMinute = startMinute
            target.defaultEndMinute = endMinute
            target.defaultDurationMinutes = nil
        case .length:
            target.defaultStartMinute = nil
            target.defaultEndMinute = nil
            target.defaultDurationMinutes = durationMinutes
        case .none:
            target.defaultStartMinute = nil
            target.defaultEndMinute = nil
            target.defaultDurationMinutes = nil
        }

        if type == .work, tracksPay {
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
        guard modelContext.saveChanges(reporting: errorReporter) else { return }

        // One memory for both editors: the next work entry or preset starts
        // from whatever was chosen here.
        if type == .work { settings.tracksPayByDefault = tracksPay }
        dismiss()
    }
}
