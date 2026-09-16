//
//  AppRouter.swift
//  Shift
//

import SwiftUI
import Observation

/// Where the app is, and what it has been asked to open.
///
/// The toolbar +, the home-screen widget and the app-icon shortcut all want the
/// same thing: the new-entry editor on Home. Routing them through one object
/// keeps that a single code path instead of three near-identical ones.
@Observable
@MainActor
final class AppRouter {
    var selectedTab: AppTab = .home
    /// Drives the editor sheet Home already owns.
    var showsNewEntry = false

    /// Posted by the scene delegate when the app icon's "New Entry" shortcut is
    /// used. The widget arrives as a `shift://new` URL instead; both land here.
    static let newEntryShortcutNotification = Notification.Name("ShiftNewEntryShortcut")

    func requestNewEntry() {
        selectedTab = .home
        showsNewEntry = true
    }

    /// Handles the widget's deep link. Unknown URLs are ignored.
    func handle(_ url: URL) {
        guard url.scheme == "shift", url.host() == "new" else { return }
        requestNewEntry()
    }
}
