//
//  MonthStepper.swift
//  Shift
//

import SwiftUI

/// Previous / month name / next, for the navigation bar of month-scoped tabs.
///
/// It only reports the step: the screen owns the month and the slide
/// direction, so the arrows and a swipe turn the page the same way.
struct MonthStepper: View {
    let displayedMonth: Date
    let step: (Int) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 2) {
            Button {
                step(-1)
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
                .accessibilityIdentifier("month-title")

            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel(Text("Next month"))
        }
    }

    private var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year().locale(locale)).localizedCapitalized
    }
}
