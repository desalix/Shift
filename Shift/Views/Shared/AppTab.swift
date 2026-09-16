//
//  AppTab.swift
//  Shift
//

import SwiftUI

/// The top-level destinations.
enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case home, income, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .income: String(localized: "Income")
        case .settings: String(localized: "Settings")
        }
    }

    /// Outline symbols: the system tab bar applies the filled variant itself.
    var symbolName: String {
        switch self {
        case .home: "calendar"
        case .income: "eurosign.circle"
        case .settings: "gearshape"
        }
    }
}
