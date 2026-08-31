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

    /// Builds the CloudKit-backed store, falling back to a local-only store if
    /// CloudKit is unavailable — an unsigned build, a simulator with no iCloud
    /// account, or a misconfigured container. Losing sync is recoverable;
    /// refusing to launch is not, so this never traps on the CloudKit path.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Event.self, Preset.self, Subject.self])

        let cloudConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.desalas.Shift")
        )

        if let container = try? ModelContainer(for: schema, configurations: [cloudConfiguration]) {
            return container
        }

        let localConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        if let container = try? ModelContainer(for: schema, configurations: [localConfiguration]) {
            return container
        }

        // Both on-disk options failed, which in practice means the store file is
        // corrupt or unreadable. An in-memory store keeps the app usable for the
        // session rather than crashing on launch.
        let memoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [memoryConfiguration])
        } catch {
            fatalError("Could not create any ModelContainer: \(error)")
        }
    }
}
