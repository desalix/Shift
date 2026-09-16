//
//  AppDelegate.swift
//  Shift
//

import SwiftUI
import UIKit

/// Home-screen quick actions are a UIKit-only API: SwiftUI has no equivalent of
/// `performActionFor`, so the app needs this much glue to receive one.
///
/// Both paths — a cold launch that starts *from* the shortcut, and a tap while
/// the app is already running — funnel into the same notification, which
/// `RootView` turns into a router request.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Cold launch: the shortcut arrives with the scene's connection options.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let shortcutItem = connectionOptions.shortcutItem else { return }
        // The scene isn't on screen yet, so let SwiftUI build its hierarchy
        // before asking it to present a sheet.
        Task { @MainActor in
            post(shortcutItem)
        }
    }

    /// Warm launch: the app was already running.
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        post(shortcutItem)
        completionHandler(true)
    }

    @MainActor
    private func post(_ shortcutItem: UIApplicationShortcutItem) {
        guard shortcutItem.type == QuickAction.newEntry else { return }
        NotificationCenter.default.post(name: AppRouter.newEntryShortcutNotification, object: nil)
    }
}

/// Mirrors the `UIApplicationShortcutItems` entry in Info.plist.
enum QuickAction {
    static let newEntry = "com.desalas.Shift.new-entry"
}
