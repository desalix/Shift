//
//  TopBar.swift
//  Shift
//

import SwiftUI

/// The shared top panel: centred title, an optional month stepper beneath it,
/// and an optional add button trailing.
///
/// The title is centred with a ZStack rather than a three-column HStack so it
/// stays optically centred regardless of whether the add button is present —
/// otherwise the title would visibly shift as you move between tabs.
struct TopBar: View {
    let tab: AppTab
    @Binding var displayedMonth: Date
    var onAdd: (() -> Void)?

    @Environment(AppSettings.self) private var settings
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Text(tab.title)
                    .font(.headline)
                    .frame(maxWidth: .infinity)

                if tab.showsAddButton, let onAdd {
                    HStack {
                        Spacer()
                        Button(action: onAdd) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .accessibilityLabel(Text("New entry"))
                    }
                }
            }

            if tab.showsMonthStepper {
                monthStepper
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var monthStepper: some View {
        HStack(spacing: 0) {
            Button {
                step(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 32)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("Previous month"))

            Text(monthTitle)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                // Without a stable identity the title would cross-fade on every
                // redraw; keying it to the month makes the transition read as a
                // deliberate step rather than a flicker.
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: displayedMonth)

            Button {
                step(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 32)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("Next month"))
        }
        .foregroundStyle(settings.accentColor.color)
    }

    private var monthTitle: String {
        displayedMonth.formatted(
            .dateTime.month(.wide).year().locale(locale)
        )
        .localizedCapitalized
    }

    private func step(by value: Int) {
        withAnimation(.snappy(duration: 0.2)) {
            displayedMonth = CalendarMath.month(byAdding: value, to: displayedMonth, calendar: calendar)
        }
    }
}
