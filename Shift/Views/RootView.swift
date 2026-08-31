//
//  RootView.swift
//  Shift
//

import SwiftUI
import SwiftData

/// The app shell: three panels, arranged by size class.
///
/// Compact (iPhone portrait) stacks top bar / content / bottom bar. Regular
/// (iPad landscape) keeps the top bar full width and moves navigation to a left
/// rail with the content to its right, per the spec.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppErrorReporter.self) private var errorReporter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.calendar) private var calendar

    @State private var selection: AppTab = .home
    @State private var displayedMonth: Date = Date()
    @State private var isPresentingEditor = false

    var body: some View {
        Group {
            if settings.hasCompletedOnboarding {
                shell
            } else {
                OnboardingView()
            }
        }
        .animation(.snappy(duration: 0.25), value: settings.hasCompletedOnboarding)
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
        VStack(spacing: 0) {
            TopBar(
                tab: selection,
                displayedMonth: $displayedMonth,
                onAdd: selection.showsAddButton ? { isPresentingEditor = true } : nil
            )

            if isRegularWidth {
                HStack(spacing: 0) {
                    SideNavBar(selection: $selection, tabs: AppTab.allCases)
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                BottomTabBar(selection: $selection, tabs: AppTab.allCases)
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $isPresentingEditor) {
            // Opening from Home creates the entry on the first day of the month
            // being viewed, unless that is the current month — then today, which
            // is almost always what the user means.
            EventEditorView(mode: .create(initialDate: defaultNewEventDate))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .home:
            HomeView(displayedMonth: $displayedMonth)
        case .assistant:
            AssistantView()
        case .income:
            IncomeView(displayedMonth: $displayedMonth)
        case .settings:
            SettingsView()
        }
    }

    /// iPhone is portrait-only per the spec, so a regular horizontal size class
    /// here means iPad (or an iPad-sized multitasking pane).
    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var defaultNewEventDate: Date {
        let now = Date()
        if calendar.isDate(displayedMonth, equalTo: now, toGranularity: .month) {
            return now
        }
        return CalendarMath.startOfMonth(for: displayedMonth, calendar: calendar)
    }
}
