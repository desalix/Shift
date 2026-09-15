//
//  SettingsView.swift
//  Shift
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @Query private var allEvents: [Event]
    @Query(sort: \Subject.name) private var subjects: [Subject]
    @Query(sort: \Preset.name) private var presets: [Preset]

    @State private var showingSchoolDisableWarning = false

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                Toggle(isOn: Binding(
                    get: { settings.schoolEnabled },
                    set: { newValue in
                        // Turning School off hides the section but must never
                        // silently discard the user's school data, so warn
                        // only when there is something to lose.
                        if !newValue, hasSchoolData {
                            showingSchoolDisableWarning = true
                        } else {
                            settings.schoolEnabled = newValue
                        }
                    }
                )) {
                    Label("School", systemImage: EventType.school.symbolName)
                }

                if settings.schoolEnabled {
                    NavigationLink {
                        SubjectsView()
                    } label: {
                        LabeledContent {
                            Text("\(subjects.count)")
                        } label: {
                            Label("Subjects", systemImage: "books.vertical")
                        }
                    }
                }
            } header: {
                Text("Sections")
            } footer: {
                Text("Work and personal calendar entries are always available.")
            }

            Section {
                NavigationLink {
                    PresetsView()
                } label: {
                    LabeledContent {
                        Text("\(presets.count)")
                    } label: {
                        Label("Manage Presets", systemImage: "square.stack.3d.up")
                    }
                }
            } header: {
                Text("Presets")
            } footer: {
                Text("Presets pre-fill the entry form. Handy for a shift you work often.")
            }

            Section("Appearance") {
                Picker(selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    Label("Theme", systemImage: "circle.lefthalf.filled")
                }

                ColorPickerRow(
                    title: String(localized: "Accent"),
                    systemImage: "paintpalette",
                    selection: $settings.accentColor
                )
                ColorPickerRow(
                    title: String(localized: "Work"),
                    systemImage: EventType.work.symbolName,
                    selection: $settings.workColor
                )
                if settings.schoolEnabled {
                    ColorPickerRow(
                        title: String(localized: "School"),
                        systemImage: EventType.school.symbolName,
                        selection: $settings.schoolColor
                    )
                }
                ColorPickerRow(
                    title: String(localized: "Calendar"),
                    systemImage: EventType.calendar.symbolName,
                    selection: $settings.calendarColor
                )
            }

            Section {
                Picker(selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                } label: {
                    Label("Language", systemImage: "globe")
                }
            } header: {
                Text("Language")
            } footer: {
                Text("Most text changes immediately. A few system-provided strings update the next time you open Shift.")
            }

            Section {
                NavigationLink {
                    AssistantSettingsView()
                } label: {
                    Label("AI Assistant", systemImage: "sparkles")
                }
            } footer: {
                Text("Connect your own Anthropic API key to enable the Assistant.")
            }

            Section("Data") {
                LabeledContent {
                    Text("\(allEvents.count)")
                } label: {
                    Label("Entries", systemImage: "calendar")
                }

                NavigationLink {
                    ExportView()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .alert(Text("Turn off School?"), isPresented: $showingSchoolDisableWarning) {
            Button(String(localized: "Turn Off"), role: .destructive) {
                settings.schoolEnabled = false
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("Your subjects and school entries are kept, but hidden until you turn School back on.")
        }
    }

    private var hasSchoolData: Bool {
        !subjects.isEmpty || allEvents.contains { $0.type == .school }
    }
}

/// A row that shows the current colour as a swatch and opens a menu of the
/// fixed palette. A full colour wheel would let the user pick something with no
/// dark-mode counterpart, which is why the palette is closed.
struct ColorPickerRow: View {
    let title: String
    let systemImage: String
    @Binding var selection: AppColor

    var body: some View {
        Picker(selection: $selection) {
            ForEach(AppColor.allCases) { option in
                Text(option.displayName).tag(option)
            }
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }
}
