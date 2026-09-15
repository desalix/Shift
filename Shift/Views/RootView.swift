//
//  RootView.swift
//  Shift
//

import SwiftUI
import SwiftData

/// The app shell: the system tab bar on iPhone, which becomes a sidebar on
/// iPad, with a system navigation stack inside each tab.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppErrorReporter.self) private var errorReporter

    @State private var selection: AppTab = .home
    /// Shared by Home and Income so switching between them keeps the month.
    @State private var displayedMonth: Date = Date()

    var body: some View {
        Group {
            if settings.hasCompletedOnboarding {
                shell
            } else {
                OnboardingView()
            }
        }
        .animation(.snappy(duration: 0.25), value: settings.hasCompletedOnboarding)
        // The widget opens `shift://todo`.
        .onOpenURL { url in
            if url.scheme == "shift", url.host() == "todo" {
                selection = .todo
            }
        }
        // Hosted at the root so a failed write is reported no matter which
        // screen — or which presented sheet — triggered it.
        .alert(
            Text("Something went wrong"),
            isPresented: Bindable(errorReporter).isPresentingError
        ) {
            Button(String(localized: "OK"), role: .cancel) { errorReporter.dismiss() }
        } message: {
            Text(errorReporter.message ?? "")
        }
    }

    private var shell: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.symbolName, value: tab) {
                    NavigationStack {
                        content(for: tab)
                            .navigationTitle(tab.title)
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(displayedMonth: $displayedMonth)
        case .assistant:
            AssistantView()
        case .todo:
            TodoView()
        case .income:
            IncomeView(displayedMonth: $displayedMonth)
        case .settings:
            SettingsView()
        }
    }
}
