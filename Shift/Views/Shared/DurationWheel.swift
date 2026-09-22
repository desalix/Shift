//
//  DurationWheel.swift
//  Shift
//

import SwiftUI
import UIKit

/// An hours-and-minutes wheel like the Clock app's timer, bound to a total in
/// minutes.
///
/// The minutes wheel loops — spinning past 59 lands on 00 — which SwiftUI's
/// wheel picker can't do. It repeats 0–59 many times, starts in the middle, and
/// quietly re-centres after every spin so the end is never reached. The "hours"
/// and "min" labels are single-row columns, so they stay put while the numbers
/// scroll.
struct DurationWheel: UIViewRepresentable {
    @Binding var minutes: Int

    private enum Column: Int, CaseIterable {
        case hours, hoursLabel, minutes, minutesLabel
    }

    private static let minuteCycles = 200
    private static var middleCycleStart: Int { (minuteCycles / 2) * 60 }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        Self.show(minutes, in: picker, animated: false)
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent = self
        if Self.displayedMinutes(in: picker) != minutes {
            Self.show(minutes, in: picker, animated: false)
        }
    }

    private static func show(_ total: Int, in picker: UIPickerView, animated: Bool) {
        let clamped = max(0, min(total, 23 * 60 + 59))
        picker.selectRow(clamped / 60, inComponent: Column.hours.rawValue, animated: animated)
        picker.selectRow(middleCycleStart + clamped % 60, inComponent: Column.minutes.rawValue, animated: animated)
    }

    private static func displayedMinutes(in picker: UIPickerView) -> Int {
        picker.selectedRow(inComponent: Column.hours.rawValue) * 60
            + picker.selectedRow(inComponent: Column.minutes.rawValue) % 60
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: DurationWheel

        init(_ parent: DurationWheel) { self.parent = parent }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { Column.allCases.count }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            switch Column(rawValue: component) {
            case .hours: 24
            case .minutes: 60 * DurationWheel.minuteCycles
            default: 1
            }
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            switch Column(rawValue: component) {
            case .hours, .minutes: 64
            default: 72
            }
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 36 }

        func pickerView(
            _ pickerView: UIPickerView,
            viewForRow row: Int,
            forComponent component: Int,
            reusing view: UIView?
        ) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            label.font = .systemFont(ofSize: 22)
            switch Column(rawValue: component) {
            case .hours:
                label.text = "\(row)"
                label.textAlignment = .right
            case .minutes:
                label.text = "\(row % 60)"
                label.textAlignment = .right
            case .hoursLabel:
                label.text = String(localized: "hours")
                label.font = .systemFont(ofSize: 17, weight: .semibold)
                label.textAlignment = .left
            case .minutesLabel:
                label.text = String(localized: "min")
                label.font = .systemFont(ofSize: 17, weight: .semibold)
                label.textAlignment = .left
            case nil:
                label.text = nil
            }
            return label
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            if component == Column.minutes.rawValue {
                // Jump back to the same minute in the middle copy, so there is
                // always room to keep spinning either way.
                pickerView.selectRow(DurationWheel.middleCycleStart + row % 60, inComponent: component, animated: false)
            }
            parent.minutes = DurationWheel.displayedMinutes(in: pickerView)
        }
    }
}
