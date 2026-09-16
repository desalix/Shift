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
    @State private var router = AppRouter()
    // Home-screen quick actions are UIKit-only; this is what receives them.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer

    init() {
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(errorReporter)
                .environment(router)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(settings.accentColor.color)
                .environment(\.locale, settings.language.locale ?? Locale.autoupdatingCurrent)
        }
        .modelContainer(container)
    }

    /// Builds the store, mirrored to the user's private CloudKit database so
    /// their calendar follows them between devices.
    ///
    /// Mirroring imposes schema rules, which the models already satisfy: every
    /// stored property has a default, every relationship is optional, and
    /// nothing is marked unique. Breaking any of those fails at container
    /// creation, not at compile time — hence the local fallback below.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Event.self, Preset.self, Subject.self])

        let syncedConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.desalas.Shift")
        )

        if let container = try? ModelContainer(for: schema, configurations: [syncedConfiguration]) {
            return container
        }

        // No iCloud account, sync disabled in Settings, or an entitlement that
        // did not survive signing. The app is fully usable without sync, so fall
        // back to a local store rather than refusing to launch.
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
