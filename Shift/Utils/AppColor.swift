//
//  AppColor.swift
//  Shift
//

import SwiftUI

/// The fixed palette used for accent, event types, and subjects.
///
/// Colours are stored by name rather than as RGB so they adapt automatically to
/// light and dark mode, stay in sync across devices as a short string, and can
/// be named by the assistant ("make school green") without inventing hex codes.
enum AppColor: String, CaseIterable, Identifiable, Sendable {
    case blue, indigo, purple, pink, red, orange, yellow, green, teal, cyan, brown, gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .cyan: .cyan
        case .brown: .brown
        case .gray: .gray
        }
    }

    var displayName: String {
        switch self {
        case .blue: String(localized: "Blue")
        case .indigo: String(localized: "Indigo")
        case .purple: String(localized: "Purple")
        case .pink: String(localized: "Pink")
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .teal: String(localized: "Teal")
        case .cyan: String(localized: "Cyan")
        case .brown: String(localized: "Brown")
        case .gray: String(localized: "Gray")
        }
    }

    /// Falls back to Apple's system blue for unknown names, which is also the
    /// app's default accent.
    static func named(_ name: String?) -> AppColor {
        guard let name, let match = AppColor(rawValue: name) else { return .blue }
        return match
    }
}
