//
//  AppSettings.swift
//  Shift
//

import SwiftUI
import Observation

/// Which appearance the app forces, independent of the system setting.
enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}

/// Supported interface languages.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case spanish = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .english: "English"
        case .spanish: "Español"
        }
    }

    var locale: Locale? {
        switch self {
        case .system: nil
        case .english: Locale(identifier: "en")
        case .spanish: Locale(identifier: "es")
        }
    }
}

/// App-wide preferences, stored in `UserDefaults`.
///
/// These used to mirror into `NSUbiquitousKeyValueStore` so they followed the
/// user between devices, but that needs the iCloud capability, which a free
/// personal Apple developer team cannot sign. Settings are now per-device. To
/// restore syncing on a paid account, mirror each `write` into the ubiquitous
/// store and observe `didChangeExternallyNotification` — guarding the callback
/// so adopted values are not echoed straight back.
@Observable
@MainActor
final class AppSettings {
    private enum Key {
        static let accentColor = "settings.accentColor"
        static let workColor = "settings.workColor"
        static let schoolColor = "settings.schoolColor"
        static let calendarColor = "settings.calendarColor"
        static let schoolEnabled = "settings.schoolEnabled"
        static let language = "settings.language"
        static let appearance = "settings.appearance"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let tracksPayByDefault = "settings.tracksPayByDefault"
    }

    private let defaults: UserDefaults

    var accentColor: AppColor { didSet { write(accentColor.rawValue, Key.accentColor) } }
    var workColor: AppColor { didSet { write(workColor.rawValue, Key.workColor) } }
    var schoolColor: AppColor { didSet { write(schoolColor.rawValue, Key.schoolColor) } }
    var calendarColor: AppColor { didSet { write(calendarColor.rawValue, Key.calendarColor) } }
    var schoolEnabled: Bool { didSet { write(schoolEnabled, Key.schoolEnabled) } }
    var language: AppLanguage { didSet { applyLanguage() } }
    var appearance: AppearanceMode { didSet { write(appearance.rawValue, Key.appearance) } }
    var hasCompletedOnboarding: Bool { didSet { write(hasCompletedOnboarding, Key.hasCompletedOnboarding) } }
    /// Seeds the editor's "Track pay" toggle for the next work entry. Hourly
    /// workers leave it on and never think about it; someone on a fixed wage
    /// switches it off once.
    var tracksPayByDefault: Bool { didSet { write(tracksPayByDefault, Key.tracksPayByDefault) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        accentColor = AppColor.named(defaults.string(forKey: Key.accentColor) ?? AppColor.blue.rawValue)
        workColor = AppColor.named(defaults.string(forKey: Key.workColor) ?? AppColor.blue.rawValue)
        schoolColor = AppColor.named(defaults.string(forKey: Key.schoolColor) ?? AppColor.green.rawValue)
        calendarColor = AppColor.named(defaults.string(forKey: Key.calendarColor) ?? AppColor.gray.rawValue)
        schoolEnabled = defaults.bool(forKey: Key.schoolEnabled)
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .system
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        // `bool(forKey:)` can't tell "never set" from "false", and the useful
        // default here is on.
        tracksPayByDefault = defaults.object(forKey: Key.tracksPayByDefault) as? Bool ?? true
    }

    /// The colour used for an event type, before any per-event override.
    func color(for type: EventType) -> AppColor {
        switch type {
        case .work: workColor
        case .school: schoolColor
        case .calendar: calendarColor
        }
    }

    /// Resolved colour for an event: its own override, else its type colour.
    func color(for event: Event) -> Color {
        if let name = event.colorName, let override = AppColor(rawValue: name) {
            return override.color
        }
        if event.type == .school, let name = event.subject?.colorName,
           let subjectColor = AppColor(rawValue: name) {
            return subjectColor.color
        }
        return color(for: event.type).color
    }

    /// The event types offered in the editor's type picker. School only appears
    /// once the user has switched it on.
    var availableEventTypes: [EventType] {
        schoolEnabled ? [.work, .school, .calendar] : [.work, .calendar]
    }

    // MARK: - Persistence

    private func write(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    private func applyLanguage() {
        write(language.rawValue, Key.language)
        // SwiftUI resolves `Text` against the environment locale immediately, but
        // `String(localized:)` reads the bundle's preferred localisation, which is
        // only re-evaluated at launch. Writing AppleLanguages makes the two agree
        // from the next launch onward; Settings tells the user as much.
        if let code = language.locale?.identifier {
            defaults.set([code], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }
}
