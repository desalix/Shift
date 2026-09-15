//
//  MonthStepper.swift
//  Shift
//

import SwiftUI

/// Previous / month name / next, for the navigation bar of month-scoped tabs.
struct MonthStepper: View {
    @Binding var displayedMonth: Date

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 2) {
            Button {
                step(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel(Text("Previous month"))

            Text(monthTitle)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 150)
                .contentTransition(.numericText())

            Button {
                step(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel(Text("Next month"))
        }
    }

    private var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year().locale(locale)).localizedCapitalized
    }

    private func step(by value: Int) {
        withAnimation(.snappy(duration: 0.2)) {
            displayedMonth = CalendarMath.month(byAdding: value, to: displayedMonth, calendar: calendar)
        }
    }
}
