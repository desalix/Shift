//
//  TodoStorage.swift
//  Shift
//
//  Compiled into both the app and the widget extension.
//

import Foundation

/// The to-do list's on-disk form, shared with the widget through the App Group.
///
/// The list is one piece of text — one entry per line — so it lives in the
/// group's `UserDefaults` rather than SwiftData. The widget can then read it
/// without opening, or even linking, the app's model store.
nonisolated enum TodoStorage {
    static let appGroup = "group.desalas.Shift"
    static let widgetKind = "TodoWidget"
    private static let textKey = "todo.text"

    private static var defaults: UserDefaults {
        // Falls back to standard defaults if the group container is missing
        // (an unsigned build), so the app keeps working without the widget.
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func loadText() -> String {
        defaults.string(forKey: textKey) ?? ""
    }

    static func save(text: String) {
        defaults.set(text, forKey: textKey)
    }

    /// Entries are the non-blank lines, trimmed, in the order they were typed.
    static func entries(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
