//
//  AppTab.swift
//  Shift
//

import SwiftUI

/// The four top-level destinations.
enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case home, assistant, income, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .assistant: String(localized: "Assistant")
        case .income: String(localized: "Income")
        case .settings: String(localized: "Settings")
        }
    }

    /// Filled variants read better at tab-bar size and keep the set visually
    /// consistent with the rest of the SF Symbols used in the app.
    var symbolName: String {
        switch self {
        case .home: "calendar"
        case .assistant: "bubble.left.and.bubble.right.fill"
        case .income: "eurosign.circle.fill"
        case .settings: "gearshape.fill"
        }
    }

    /// Only Home and Income are scoped to a month, so only they get the stepper.
    var showsMonthStepper: Bool {
        self == .home || self == .income
    }

    /// Only Home can create an entry from the top bar.
    var showsAddButton: Bool {
        self == .home
    }
}
