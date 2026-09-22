//
//  EventEditorView.swift
//  Shift
//

import SwiftUI
import SwiftData

/// Create or edit an entry.
///
/// The form is driven by the type slider at the top: choosing Work, School, or
/// Calendar swaps which fields are shown *and* which ones are required. Notes
/// is the only always-optional field.
struct EventEditorView: View {
    enum Mode: Identifiable {
        /// `type` preselects the segmented picker — the day sheet's
        /// "Add work day" button uses it so Work is already chosen.
        case create(initialDate: Date, type: EventType?)
        case edit(Event)

        var id: String {
            switch self {
            case .create(let date, let type): "create-\(date.timeIntervalSinceReferenceDate)-\(type?.rawValue ?? "any")"
            case .edit(let event): "edit-\(event.id.uuidString)"
            }
        }

        var isEditing: Bool {
            if case .edit = self { return true }
            return false
        }
    }

    let mode: Mode

    @Environment(\.modelContext) private var modelContext
    @Environment(AppErrorReporter.self) private var errorReporter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(AppSettings.self) private var settings

    @Query(sort: \Subject.name) private var subjects: [Subject]
    @Query(sort: \Preset.name) private var presets: [Preset]

    @State private var draft = Draft()
    @State private var quickAddText = ""
    @State private var quickAddFailed = false
    @State private var didLoad = false
    @State private var showValidation = false
    @State private var newSubjectName = ""
    @State private var isAddingSubject = false
    @State private var isChoosingEditScope = false

    var body: some View {
        NavigationStack {
            Form {
                if !mode.isEditing { quickAddSection }
                typeSection
                if !applicablePresets.isEmpty { presetSection }
                detailsSection
                timingSection
                if draft.type == .work {
                    PayFields(
                        tracksPay: $draft.tracksPay,
                        compensationType: $draft.compensationType,
                        rateText: $draft.rateText,
                        durationMinutes: max(0, Int(draft.endDate.timeIntervalSince(draft.startDate) / 60))
                    )
                }
                if draft.type == .school { schoolSection }
                appearanceSection
                recurrenceSection
                notesSection
                if showValidation && !validationErrors.isEmpty { errorSection }
            }
            .navigationTitle(mode.isEditing ? Text("Edit Entry") : Text("New Entry"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: loadIfNeeded)
            .confirmationDialog(
                Text("Apply changes to?"),
                isPresented: $isChoosingEditScope,
                titleVisibility: .visible
            ) {
                Button(String(localized: "This Entry Only")) {
                    commit(scope: .thisOccurrence)
                }
                Button(String(localized: "All in Series")) {
                    commit(scope: .wholeSeries)
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text("This entry repeats. Changing the whole series keeps each occurrence on its own date, but updates its time and details.")
            }
        }
    }

    // MARK: - Sections

    /// Type the entry in one line instead of filling the form.
    ///
    /// It fills the fields below rather than saving anything, so whatever it
    /// gets wrong is visible and correctable before it becomes an entry.
    private var quickAddSection: some View {
        Section {
            HStack {
                TextField("work thursday 9-17 at 12.50/h", text: $quickAddText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(applyQuickAdd)

                if !quickAddText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: applyQuickAdd) {
                        Image(systemName: "wand.and.stars")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Fill the form"))
                }
            }
        } header: {
            Text("Quick add")
        } footer: {
            Text(quickAddFailed
                 ? String(localized: "Couldn't find a time in that. Try something like \"thursday 9-17\".")
                 : String(localized: "Type it in plain language and the form fills itself. Works offline."))
                .foregroundStyle(quickAddFailed ? Color.orange : Color.secondary)
        }
    }

    private var typeSection: some View {
        Section {
            Picker("Type", selection: $draft.type) {
                ForEach(settings.availableEventTypes) { type in
                    Text(typeName(type)).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: draft.type) { _, newValue in
                draft.applyTypeDefaults(newValue)
            }
        }
    }

    private var presetSection: some View {
        Section("Preset") {
            Picker("Preset", selection: $draft.presetID) {
                Text("None").tag(UUID?.none)
                ForEach(applicablePresets) { preset in
                    Text(preset.name).tag(UUID?.some(preset.id))
                }
            }
            .onChange(of: draft.presetID) { _, newValue in
                guard let newValue, let preset = presets.first(where: { $0.id == newValue }) else { return }
                draft.apply(preset: preset, calendar: calendar)
            }

            if let presetID = draft.presetID,
               let preset = presets.first(where: { $0.id == presetID }) {
                Text(preset.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        // An exam is titled by its subject, so there is nothing to type here.
        if !(draft.type == .school && draft.schoolKind == .exam) {
            Section("Title") {
                TextField("Title", text: $draft.title)
                    .textInputAutocapitalization(.sentences)
            }
        }
    }

    private var timingSection: some View {
        Section("When") {
            DatePicker("Starts", selection: $draft.startDate)
                .onChange(of: draft.startDate) { oldValue, newValue in
                    // Drag the end along with the start so the duration the user
                    // already set is preserved instead of silently inverting.
                    let delta = newValue.timeIntervalSince(oldValue)
                    if draft.endDate <= newValue {
                        draft.endDate = draft.endDate.addingTimeInterval(delta)
                    }
                }
            DatePicker("Ends", selection: $draft.endDate)

            if draft.endDate > draft.startDate {
                HStack {
                    Text("Duration").foregroundStyle(.secondary)
                    Spacer()
                    Text(durationText).monospacedDigit()
                }
                .font(.footnote)
            }
        }
    }

    private var schoolSection: some View {
        Section("School") {
            Picker("Kind", selection: $draft.schoolKind) {
                Text("Exam").tag(SchoolEventKind.exam)
                Text("Assignment").tag(SchoolEventKind.assignment)
                Text("Other").tag(SchoolEventKind.other)
            }
            .pickerStyle(.segmented)

            Picker("Subject", selection: $draft.subjectID) {
                Text("None").tag(UUID?.none)
                ForEach(subjects) { subject in
                    Text(subject.name).tag(UUID?.some(subject.id))
                }
            }

            // Quick-add keeps the user in the editor: creating a subject
            // mid-entry shouldn't mean abandoning a half-filled form.
            if isAddingSubject {
                HStack {
                    TextField("New subject", text: $newSubjectName)
                        .textInputAutocapitalization(.words)
                        .onSubmit(commitNewSubject)
                    Button("Add", action: commitNewSubject)
                        .disabled(newSubjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderless)
                }
            } else {
                Button {
                    isAddingSubject = true
                } label: {
                    Label("Quick Add Subject", systemImage: "plus.circle")
                }
            }
        }
    }

    private var recurrenceSection: some View {
        Section("Repeat") {
            Toggle("Repeat weekly", isOn: $draft.isRecurring)
                .disabled(mode.isEditing)

            if draft.isRecurring {
                WeekdaySelector(selection: $draft.recurringWeekdays, calendar: calendar, locale: locale)
                DatePicker("Until", selection: $draft.recurringEndDate, displayedComponents: .date)

                Text("Creates a separate entry for each occurrence, so you can edit or delete any one of them on its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if mode.isEditing, draft.isRecurring {
                Text("Repeat settings can't be changed after an entry is created. Delete the series and add it again to change them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appearanceSection: some View {
        Section("Colour") {
            Picker("Colour", selection: $draft.colorName) {
                Text("Default").tag(String?.none)
                ForEach(AppColor.allCases) { option in
                    Text(option.displayName).tag(String?.some(option.rawValue))
                }
            }
        }
    }

    private var notesSection: some View {
        Section {
            TextField("Notes", text: $draft.notes, axis: .vertical)
                .lineLimit(3 ... 8)
                .onChange(of: draft.notes) { _, newValue in
                    // Enforce the cap at the point of entry rather than only at
                    // save, so the counter can never show an invalid state.
                    if newValue.count > Event.notesCharacterLimit {
                        draft.notes = String(newValue.prefix(Event.notesCharacterLimit))
                    }
                }
        } header: {
            Text("Notes")
        } footer: {
            HStack {
                Text("Optional. Special requirements, what to bring, anything else.")
                Spacer()
                Text("\(draft.notes.count)/\(Event.notesCharacterLimit)")
                    .monospacedDigit()
                    .foregroundStyle(draft.notes.count >= Event.notesCharacterLimit ? .orange : .secondary)
            }
        }
    }

    private var errorSection: some View {
        Section {
            ForEach(validationErrors, id: \.self) { error in
                Label {
                    Text(error.errorDescription ?? "")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.footnote)
            }
        }
    }

    // MARK: - Derived state

    private var applicablePresets: [Preset] {
        presets.filter { $0.type == draft.type }
    }

    private var selectedSubject: Subject? {
        guard let id = draft.subjectID else { return nil }
        return subjects.first { $0.id == id }
    }

    private var validationErrors: [Event.ValidationError] {
        Event.validate(
            title: draft.title,
            type: draft.type,
            startDate: draft.startDate,
            endDate: draft.endDate,
            compensationType: draft.type == .work ? draft.compensationType : nil,
            hourlyRateCents: draft.type == .work && draft.compensationType == .hourly
                ? Money.cents(from: draft.rateText) : nil,
            fixedRateCents: draft.type == .work && draft.compensationType == .fixed
                ? Money.cents(from: draft.rateText) : nil,
            schoolKind: draft.type == .school ? draft.schoolKind : nil,
            subject: draft.type == .school ? selectedSubject : nil,
            notes: draft.notes.isEmpty ? nil : draft.notes
        )
    }

    private var durationText: String {
        let minutes = max(0, Int(draft.endDate.timeIntervalSince(draft.startDate) / 60))
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 && remainder > 0 { return String(localized: "\(hours)h \(remainder)m") }
        if hours > 0 { return String(localized: "\(hours)h") }
        return String(localized: "\(remainder)m")
    }


    private func typeName(_ type: EventType) -> String {
        switch type {
        case .work: String(localized: "Work")
        case .school: String(localized: "School")
        case .calendar: String(localized: "Calendar")
        }
    }

    // MARK: - Actions

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        switch mode {
        case .create(let date, let type):
            draft = Draft(
                initialDate: date,
                calendar: calendar,
                defaultType: type ?? settings.availableEventTypes.first ?? .calendar,
                tracksPay: settings.tracksPayByDefault
            )
        case .edit(let event):
            draft = Draft(event: event)
        }
    }

    private func applyQuickAdd() {
        guard let parsed = QuickAddParser.parse(quickAddText, calendar: calendar) else {
            quickAddFailed = true
            return
        }

        quickAddFailed = false
        draft.title = parsed.title
        // Only adopt a type the user actually has switched on, so a stray
        // "exam" cannot select School while School is disabled.
        if settings.availableEventTypes.contains(parsed.type) {
            draft.type = parsed.type
        }
        draft.startDate = parsed.startDate
        draft.endDate = parsed.endDate

        if draft.type == .work, let cents = parsed.hourlyRateCents {
            draft.tracksPay = true
            draft.compensationType = .hourly
            draft.rateText = Money.editableString(cents: cents)
        }

        if let weekday = parsed.repeatsOnWeekday {
            draft.isRecurring = true
            draft.recurringWeekdays = [weekday]
        }

        quickAddText = ""
    }

    private func commitNewSubject() {
        let name = newSubjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        // Reuse an existing subject with the same name rather than creating a
        // near-duplicate the user would then have to reconcile.
        if let existing = subjects.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            draft.subjectID = existing.id
        } else {
            let subject = Subject(name: name)
            modelContext.insert(subject)
            modelContext.saveChanges(reporting: errorReporter)
            draft.subjectID = subject.id
        }

        newSubjectName = ""
        isAddingSubject = false
    }

    private func save() {
        guard validationErrors.isEmpty else {
            showValidation = true
            return
        }

        // Editing one occurrence of a series is ambiguous in the same way
        // deleting one is, so it asks the same question rather than silently
        // picking the narrower reading.
        if case .edit(let event) = mode, EventSeries.hasSiblings(event, context: modelContext) {
            isChoosingEditScope = true
            return
        }

        commit(scope: .thisOccurrence)
    }

    private func commit(scope: EventSeries.Scope) {
        // Whatever was chosen here becomes the default for the next shift, so
        // an hourly worker never touches the toggle and a salaried one sets it
        // once.
        if draft.type == .work { settings.tracksPayByDefault = draft.tracksPay }

        switch mode {
        case .edit(let event):
            draft.write(into: event, subject: selectedSubject, preset: selectedPreset)
            event.touch()
            if scope == .wholeSeries {
                EventSeries.propagate(from: event, context: modelContext, calendar: calendar)
            }
        case .create:
            insertNewEvents()
        }

        // Stay open if the write failed, so the user's work survives and they
        // can retry rather than watching the sheet close on a lost entry.
        guard modelContext.saveChanges(reporting: errorReporter) else { return }
        dismiss()
    }

    private var selectedPreset: Preset? {
        guard let id = draft.presetID else { return nil }
        return presets.first { $0.id == id }
    }

    /// Creates the entry — or, for a weekly rule, one entry per occurrence
    /// sharing a `recurrenceID`.
    private func insertNewEvents() {
        let subject = selectedSubject
        let preset = selectedPreset

        guard draft.isRecurring, !draft.recurringWeekdays.isEmpty else {
            let event = Event()
            draft.write(into: event, subject: subject, preset: preset)
            modelContext.insert(event)
            return
        }

        let occurrences = Recurrence.occurrences(
            start: draft.startDate,
            end: draft.endDate,
            weekdays: Array(draft.recurringWeekdays),
            until: draft.recurringEndDate,
            calendar: calendar
        )

        // A rule that matches no dates would otherwise silently create nothing;
        // fall back to the single entry the user actually filled in.
        guard !occurrences.isEmpty else {
            let event = Event()
            draft.write(into: event, subject: subject, preset: preset)
            event.isRecurring = false
            modelContext.insert(event)
            return
        }

        let groupID = UUID()
        for occurrence in occurrences {
            let event = Event()
            draft.write(into: event, subject: subject, preset: preset)
            event.startDate = occurrence.start
            event.endDate = occurrence.end
            event.recurrenceID = groupID
            modelContext.insert(event)
        }
    }
}
