//
//  ShiftApp.swift
//  Shift
//

import SwiftUI
import SwiftData
import os

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
                .environment(\.locale, settings.language.locale())
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
    private static let cloudKitContainer = "iCloud.com.desalas.ShiftApp"

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Event.self, Preset.self, Subject.self])

        #if DEBUG && !targetEnvironment(simulator)
        // Must run before the real container exists. See the type for why.
        CloudKitSchemaInitializer.runIfNeeded(
            containerIdentifier: cloudKitContainer,
            types: [Event.self, Preset.self, Subject.self]
        )
        #endif

        let syncedConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(cloudKitContainer)
        )

        do {
            return try ModelContainer(for: schema, configurations: [syncedConfiguration])
        } catch {
            // The fallback below keeps the app usable, which also makes this
            // failure invisible. Log it, so a broken schema or entitlement shows
            // up in the console instead of as sync that quietly never happens.
            Logger(subsystem: "com.desalas.Shift", category: "sync")
                .error("CloudKit sync unavailable, using a local store: \(String(reflecting: error), privacy: .public)")
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
