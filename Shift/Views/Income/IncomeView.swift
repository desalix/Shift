//
//  IncomeView.swift
//  Shift
//

import SwiftUI
import SwiftData

/// The month's paycheck, with the shifts that make it up listed underneath.
///
/// Gross only, work entries only: a shift counts toward the month its *start*
/// falls in, so an overnight shift on the 31st is paid in that month rather
/// than split across two.
struct IncomeView: View {
    @Binding var displayedMonth: Date

    @Environment(\.calendar) private var calendar

    var body: some View {
        // The stack exists purely so rows can push a detail view; the app draws
        // its own top bar, so the navigation bar is hidden at the root and only
        // appears once something is pushed onto it.
        NavigationStack {
            MonthIncome(month: displayedMonth)
                .id(CalendarMath.startOfMonth(for: displayedMonth, calendar: calendar))
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct MonthIncome: View {
    let month: Date

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(AppSettings.self) private var settings

    @Query private var workEvents: [Event]

    init(month: Date) {
        self.month = month

        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = .autoupdatingCurrent
        let start = CalendarMath.startOfMonth(for: month, calendar: calendar)
        let end = CalendarMath.startOfNextMonth(for: month, calendar: calendar)
        let workRaw = EventType.work.rawValue

        _workEvents = Query(
            filter: #Predicate<Event> { event in
                event.typeRaw == workRaw && event.startDate >= start && event.startDate < end
            },
            sort: [SortDescriptor(\Event.startDate)]
        )
    }

    var body: some View {
        Group {
            if payingEvents.isEmpty {
                ContentUnavailableView {
                    Label("No income this month", systemImage: "eurosign.circle")
                } description: {
                    Text("Work entries with an hourly or fixed rate will appear here.")
                }
            } else {
                List {
                    Section { summaryCard.listRowInsets(EdgeInsets()) }
                        .listRowBackground(Color.clear)

                    Section {
                        ForEach(payingEvents) { event in
                            NavigationLink {
                                EventDetailView(event: event)
                            } label: {
                                IncomeRow(event: event)
                            }
                        }
                    } header: {
                        Text("\(payingEvents.count) shifts")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 6) {
            Text("Gross this month")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(Money.string(cents: totalCents, locale: locale))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            HStack(spacing: 16) {
                StatPill(
                    title: String(localized: "Hours"),
                    value: hoursText
                )
                StatPill(
                    title: String(localized: "Shifts"),
                    value: "\(payingEvents.count)"
                )
                if let average = averageHourlyCents {
                    StatPill(
                        title: String(localized: "Avg/hour"),
                        value: Money.string(cents: average, locale: locale)
                    )
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Totals

    /// Work entries that actually contribute money. A rate-less work entry is
    /// still a real shift, but listing it under a paycheck total with €0 would
    /// only be confusing.
    private var payingEvents: [Event] {
        workEvents.filter { $0.earningsInCents > 0 }
    }

    private var totalCents: Int {
        payingEvents.reduce(0) { $0 + $1.earningsInCents }
    }

    private var totalMinutes: Int {
        payingEvents.reduce(0) { $0 + $1.durationInMinutes }
    }

    private var hoursText: String {
        let hours = Double(totalMinutes) / 60.0
        return hours.formatted(.number.precision(.fractionLength(0 ... 1)).locale(locale))
    }

    /// Blended rate across the month. Only meaningful once there is measurable
    /// time — a month of purely fixed-rate one-off jobs has no hourly figure.
    private var averageHourlyCents: Int? {
        guard totalMinutes > 0 else { return nil }
        return Int((Double(totalCents) * 60.0 / Double(totalMinutes)).rounded())
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct IncomeRow: View {
    let event: Event

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(event.startDate.formatted(.dateTime.day().locale(locale)))
                    .font(.headline)
                    .monospacedDigit()
                Text(event.startDate.formatted(.dateTime.weekday(.abbreviated).locale(locale)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(event.timeRangeText(calendar: calendar, locale: locale))
                    if let rate = event.rateText {
                        Text("·")
                        Text(rate)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(Money.string(cents: event.earningsInCents, locale: locale))
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 3)
    }
}
