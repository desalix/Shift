//
//  ShiftApp.swift
//  Shift
//

import SwiftUI
import SwiftData

@main
struct ShiftApp: App {
    @State private var settings = AppSettings()
    @State private var errorReporter = AppErrorReporter()
    private let container: ModelContainer

    init() {
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(errorReporter)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(settings.accentColor.color)
                .environment(\.locale, settings.language.locale ?? Locale.autoupdatingCurrent)
        }
        .modelContainer(container)
    }

    /// Builds the on-device store.
    ///
    /// Deliberately local-only: CloudKit sync needs the iCloud capability, which
    /// a free personal Apple developer team cannot sign, so declaring it made
    /// the app impossible to install on a real device. To restore cross-device
    /// sync on a paid account, re-add the iCloud + Push capabilities and pass
    /// `cloudKitDatabase: .private("iCloud.<bundle-id>")` here.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Event.self, Preset.self, Subject.self])

        let localConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        if let container = try? ModelContainer(for: schema, configurations: [localConfiguration]) {
            return container
        }

        // The on-disk store failed, which in practice means the file is corrupt
        // or unreadable. An in-memory store keeps the app usable for the session
        // rather than crashing on launch.
        let memoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [memoryConfiguration])
        } catch {
            fatalError("Could not create any ModelContainer: \(error)")
        }
    }
}
