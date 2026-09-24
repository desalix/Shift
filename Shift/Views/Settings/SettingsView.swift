//
//  SettingsView.swift
//  Shift
//

import SwiftUI
import SwiftData

/// The Settings tab: General and School lead to their own pages; Presets and
/// Data sit here directly. No section headers — each row names itself.
struct SettingsView: View {
    @Query private var allEvents: [Event]
    @Query(sort: \Preset.name) private var presets: [Preset]

    var body: some View {
        List {
            Section {
                NavigationLink {
                    GeneralSettingsView()
                } label: {
                    Label("General", systemImage: "gearshape")
                }
            }

            Section {
                NavigationLink {
                    SchoolSettingsView()
                } label: {
                    Label("School", systemImage: EventType.school.symbolName)
                }
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
            } footer: {
                Text("Presets pre-fill the entry form. Handy for a shift you work often.")
            }

            Section {
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
    }
}

/// Language and appearance.
struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                Picker(selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                } label: {
                    Label("Language", systemImage: "globe")
                }
            } footer: {
                Text("Most text changes immediately. A few system-provided strings update the next time you open Shift.")
            }

            Section {
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
        }
        .navigationTitle(Text("General"))
        .navigationBarTitleDisplayMode(.inline)
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
                    .foregroundStyle(selection.color)
            }
        }
        // A menu picker draws its selected value in the tint, so the colour's
        // name appears in that colour.
        .tint(selection.color)
    }
}
