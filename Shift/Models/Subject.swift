//
//  Subject.swift
//  Shift
//

import Foundation
import SwiftData

/// A school subject. Only meaningful when School is enabled in Settings.
///
/// Deleting a subject cascades to every event linked to it, which is why the
/// UI puts that behind an explicit confirmation.
@Model
final class Subject {
    var id: UUID = UUID()
    var name: String = ""
    var colorName: String?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Event.subject)
    var events: [Event]?

    /// Presets that fill in this subject. Nothing reads it; it exists because
    /// CloudKit mirroring rejects any relationship without an inverse, and
    /// `Preset.subject` had none — which silently disabled sync. Nullify, so
    /// deleting a subject leaves its presets in place, just unlinked.
    @Relationship(deleteRule: .nullify, inverse: \Preset.subject)
    var presets: [Preset]?

    init(id: UUID = UUID(), name: String = "", colorName: String? = nil) {
        self.id = id
        self.name = name
        self.colorName = colorName
        self.createdAt = Date()
    }

    var eventCount: Int { events?.count ?? 0 }
}
