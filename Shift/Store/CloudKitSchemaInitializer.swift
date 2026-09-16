//
//  CloudKitSchemaInitializer.swift
//  Shift
//

#if DEBUG && !targetEnvironment(simulator)
import CoreData
import SwiftData
import os

/// Declares the *complete* schema in CloudKit's Development environment.
///
/// CloudKit learns a field only when a record arrives carrying it, and an
/// optional left empty is never sent. Deploy after casual testing and
/// Production lacks those fields; Production schemas can't grow on their own,
/// so the first user who, say, adds a note gets a record that won't sync.
/// `initializeCloudKitSchema` declares every entity and attribute up front.
///
/// Debug builds on a real device only, once per schema version. Release builds
/// don't contain this type at all.
enum CloudKitSchemaInitializer {
    /// Bump whenever the models change, so the next debug run on a device
    /// re-declares the schema before it is deployed to Production again.
    private static let schemaVersion = 1
    private static let defaultsKey = "debug.cloudKitSchemaInitializedVersion"

    static func runIfNeeded(containerIdentifier: String, types: [any PersistentModel.Type]) {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: defaultsKey) < schemaVersion else { return }

        let logger = Logger(subsystem: "com.desalas.Shift", category: "sync")

        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: types) else {
            logger.error("CloudKit schema: could not build a managed object model")
            return
        }

        // A throwaway store: only the schema matters here, never the data.
        let url = FileManager.default.temporaryDirectory.appending(path: "cloudkit-schema.store")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: containerIdentifier
        )
        description.shouldAddStoreAsynchronously = false

        let container = NSPersistentCloudKitContainer(name: "CloudKitSchema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }

        if let loadError {
            logger.error("CloudKit schema: store failed to load: \(String(reflecting: loadError), privacy: .public)")
        } else {
            do {
                try container.initializeCloudKitSchema(options: [])
                defaults.set(schemaVersion, forKey: defaultsKey)
                logger.notice("CloudKit schema: declared every record type and field in Development")
            } catch {
                logger.error("CloudKit schema: initialisation failed: \(String(reflecting: error), privacy: .public)")
            }
        }

        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(filePath: url.path() + suffix))
        }
    }
}
#endif
