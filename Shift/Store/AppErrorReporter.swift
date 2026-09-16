//
//  AppErrorReporter.swift
//  Shift
//

import Foundation
import SwiftData
import Observation
import OSLog

/// Collects failures that the user needs to know about.
///
/// A calendar people rely on must not lose an entry quietly. Writes were
/// previously `try?`-ed away, so a failed save — a full disk, a CloudKit
/// constraint violation, a corrupt store — looked exactly like success: the
/// sheet dismissed and the entry vanished. This surfaces those instead.
@Observable
@MainActor
final class AppErrorReporter {
    private(set) var message: String?

    @ObservationIgnored
    private let logger = Logger(subsystem: "com.desalas.Shift", category: "persistence")

    var isPresentingError: Bool {
        get { message != nil }
        set { if !newValue { message = nil } }
    }

    func report(_ error: Error, while action: String) {
        logger.error("\(action, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        message = String(localized: "\(action) failed. \(error.localizedDescription)")
    }

    func dismiss() {
        message = nil
    }
}

extension ModelContext {
    /// Saves, reporting any failure rather than discarding it.
    ///
    /// Returns whether the save succeeded so callers can decide whether to
    /// dismiss a sheet — dismissing on a failed write is what made the old
    /// `try? save()` calls look like they had worked.
    @MainActor
    @discardableResult
    func saveChanges(
        reporting reporter: AppErrorReporter?,
        while action: String = String(localized: "Saving")
    ) -> Bool {
        guard hasChanges else { return true }
        do {
            try save()
            return true
        } catch {
            reporter?.report(error, while: action)
            return false
        }
    }
}
