//
//  PayFields.swift
//  Shift
//

import SwiftUI

/// The Pay section, shared by the entry and preset editors so the two can't
/// drift apart: a Track pay switch, then the rate only when pay is tracked.
struct PayFields: View {
    @Binding var tracksPay: Bool
    @Binding var compensationType: CompensationType
    @Binding var rateText: String
    /// When known, an hourly rate also shows what it comes to for this length.
    var durationMinutes: Int?

    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            Toggle("Track pay", isOn: $tracksPay)

            if tracksPay {
                Picker("Rate type", selection: $compensationType) {
                    Text("Hourly").tag(CompensationType.hourly)
                    Text("Fixed").tag(CompensationType.fixed)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text(compensationType == .hourly
                         ? String(localized: "Hourly rate")
                         : String(localized: "Fixed amount"))
                    Spacer()
                    TextField("0.00", text: $rateText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                    Text(Money.currencySymbol).foregroundStyle(.secondary)
                }

                if compensationType == .hourly,
                   let cents = Money.cents(from: rateText), cents > 0,
                   let minutes = durationMinutes, minutes > 0 {
                    HStack {
                        Text("Estimated earnings").foregroundStyle(.secondary)
                        Spacer()
                        Text(Money.string(cents: Int((Double(minutes * cents) / 60.0).rounded()), locale: locale))
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    .font(.footnote)
                }
            }
        } header: {
            Text("Pay")
        } footer: {
            if !tracksPay {
                Text("This shift records time only. It still appears in Income, without an amount.")
            }
        }
    }
}
