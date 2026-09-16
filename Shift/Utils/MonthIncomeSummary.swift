//
//  MonthIncomeSummary.swift
//  Shift
//

import Foundation

/// The month's totals, derived from its work entries.
///
/// Pay is optional, so a month mixes shifts that earn money with shifts that
/// only record time. Both count as work and both show in the list, but only
/// paid time may inform the hourly average — otherwise unpaid hours would drag
/// it toward zero and read as a bug rather than a deliberate blank.
struct MonthIncomeSummary: Equatable {
    let totalCents: Int
    let totalMinutes: Int
    let paidMinutes: Int
    let shiftCount: Int

    init(workEvents: [Event]) {
        totalCents = workEvents.reduce(0) { $0 + $1.earningsInCents }
        totalMinutes = workEvents.reduce(0) { $0 + $1.durationInMinutes }
        paidMinutes = workEvents
            .filter { $0.earningsInCents > 0 }
            .reduce(0) { $0 + $1.durationInMinutes }
        shiftCount = workEvents.count
    }

    /// Blended rate across the paid shifts, or nil when nothing measurable was
    /// paid — a month of purely unpaid or purely fixed-fee work has no hourly
    /// figure to report.
    var averageHourlyCents: Int? {
        guard paidMinutes > 0, totalCents > 0 else { return nil }
        return Int((Double(totalCents) * 60.0 / Double(paidMinutes)).rounded())
    }

    var totalHours: Double { Double(totalMinutes) / 60.0 }
}
