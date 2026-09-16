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
        MonthIncome(month: displayedMonth)
            .id(CalendarMath.startOfMonth(for: displayedMonth, calendar: calendar))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    MonthStepper(displayedMonth: $displayedMonth)
                }
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
            if workEvents.isEmpty {
                ContentUnavailableView {
                    Label("No income this month", systemImage: "eurosign.circle")
                } description: {
                    Text("Work entries will appear here.")
                }
            } else {
                List {
                    Section { summaryCard.listRowInsets(EdgeInsets()) }
                        .listRowBackground(Color.clear)

                    Section {
                        ForEach(workEvents) { event in
                            NavigationLink {
                                EventDetailView(event: event)
                            } label: {
                                IncomeRow(event: event)
                            }
                        }
                    } header: {
                        Text("\(summary.shiftCount) shifts")
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

            Text(Money.string(cents: summary.totalCents, locale: locale))
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
                    value: "\(summary.shiftCount)"
                )
                if let average = summary.averageHourlyCents {
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

    /// Every work entry in the month, paid or not: an unpaid shift is still a
    /// shift, and hiding it made worked time disappear from the one screen that
    /// is about worked time.
    private var summary: MonthIncomeSummary {
        MonthIncomeSummary(workEvents: workEvents)
    }

    private var hoursText: String {
        summary.totalHours.formatted(.number.precision(.fractionLength(0 ... 1)).locale(locale))
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

            if event.earningsInCents > 0 {
                Text(Money.string(cents: event.earningsInCents, locale: locale))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            } else {
                // Worked, but no pay recorded — a dash rather than €0.
                Text(verbatim: "—")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}
