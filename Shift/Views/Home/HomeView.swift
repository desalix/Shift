//
//  HomeView.swift
//  Shift
//

import SwiftUI
import SwiftData

/// The month calendar. Fixed layout: each month's grid fills the available
/// space exactly, and there is no zooming. Months sit side by side, so a
/// horizontal drag pulls the next or previous one in under the finger.
struct HomeView: View {
    @Binding var displayedMonth: Date

    @Environment(\.calendar) private var calendar
    @Environment(AppRouter.self) private var router

    var body: some View {
        // One grid per page, each with its own `@Query` over its month.
        MonthPager(month: $displayedMonth) { month in
            MonthGrid(month: month)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                MonthStepper(displayedMonth: displayedMonth, step: step)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.requestNewEntry()
                } label: {
                    Label("New entry", systemImage: "plus")
                }
            }
        }
        // The toolbar +, the widget and the app-icon shortcut all raise the
        // same flag, so they open one sheet rather than three.
        .sheet(isPresented: Bindable(router).showsNewEntry) {
            EventEditorView(mode: .create(initialDate: defaultNewEventDate, type: nil))
        }
    }

    /// The toolbar arrows: the pager scrolls to follow.
    private func step(_ offset: Int) {
        displayedMonth = CalendarMath.month(byAdding: offset, to: displayedMonth, calendar: calendar)
    }

    /// Today when viewing the current month — almost always what the user
    /// means — otherwise the first day of the month on screen.
    private var defaultNewEventDate: Date {
        let now = Date()
        if calendar.isDate(displayedMonth, equalTo: now, toGranularity: .month) {
            return now
        }
        return CalendarMath.startOfMonth(for: displayedMonth, calendar: calendar)
    }
}

private struct MonthGrid: View {
    let month: Date

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(AppSettings.self) private var settings

    @Query private var events: [Event]

    @State private var selectedDay: SelectedDay?

    init(month: Date) {
        self.month = month

        // The query has to cover the whole visible grid, not just the month,
        // because the first and last rows show days from the adjacent months.
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = .autoupdatingCurrent
        let days = CalendarMath.monthGridDays(for: month, calendar: calendar)
        let lower = days.first ?? CalendarMath.startOfMonth(for: month, calendar: calendar)
        let upper = calendar.date(byAdding: .day, value: 1, to: days.last ?? lower) ?? lower

        // Overlap test, so an entry that starts before the window but runs into
        // it still shows on the days it covers.
        _events = Query(
            filter: #Predicate<Event> { event in
                event.startDate < upper && event.endDate >= lower
            },
            sort: [SortDescriptor(\Event.startDate), SortDescriptor(\Event.title)]
        )
    }

    var body: some View {
        GeometryReader { proxy in
            // Bucketed once per body pass. Reading the computed property from
            // inside the cell loop instead would re-bucket every event for all
            // 42 cells on every redraw.
            let buckets = eventsByDay
            let days = CalendarMath.monthGridDays(for: month, calendar: calendar)
            let weekCount = max(1, days.count / 7)
            let headerHeight: CGFloat = 26
            let spacing: CGFloat = 1
            let availableHeight = proxy.size.height - headerHeight
            let rowHeight = max(52, (availableHeight - spacing * CGFloat(weekCount - 1)) / CGFloat(weekCount))

            VStack(spacing: 0) {
                weekdayHeader
                    .frame(height: headerHeight)

                VStack(spacing: spacing) {
                    ForEach(0 ..< weekCount, id: \.self) { week in
                        HStack(spacing: spacing) {
                            ForEach(0 ..< 7, id: \.self) { weekday in
                                let index = week * 7 + weekday
                                if index < days.count {
                                    let day = days[index]
                                    DayCell(
                                        day: day,
                                        events: buckets[calendar.startOfDay(for: day)] ?? [],
                                        isInDisplayedMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                                        isToday: calendar.isDateInToday(day)
                                    )
                                    .frame(height: rowHeight)
                                    .frame(maxWidth: .infinity)
                                    .contentShape(.rect)
                                    .onTapGesture { selectedDay = SelectedDay(date: day) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(Color(.separator))
        .sheet(item: $selectedDay) { selection in
            DayEventsView(day: selection.date)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 1) {
            ForEach(Array(CalendarMath.weekdaySymbols(calendar: calendar, locale: locale).enumerated()), id: \.offset) { _, symbol in
                Text(symbol.localizedUppercase)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 5)
        .background(Color(.systemGroupedBackground))
    }

    /// Buckets each event into every day it covers, so a shift running past
    /// midnight appears on both days.
    private var eventsByDay: [Date: [Event]] {
        var buckets: [Date: [Event]] = [:]
        for event in events where settings.shows(event) {
            let firstDay = calendar.startOfDay(for: event.startDate)
            // An event ending exactly at midnight belongs to the previous day,
            // not to the day it technically touches for zero seconds.
            let lastMoment = event.endDate > event.startDate
                ? event.endDate.addingTimeInterval(-1)
                : event.endDate
            let lastDay = calendar.startOfDay(for: lastMoment)

            var cursor = firstDay
            var guardCounter = 0
            while cursor <= lastDay, guardCounter < 400 {
                buckets[cursor, default: []].append(event)
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
                guardCounter += 1
            }
        }
        return buckets
    }
}

/// Wrapper so a tapped day can drive `sheet(item:)`.
///
/// Conforming `Date` itself would mean adding a public conformance to a
/// Foundation type app-wide, which leaks out of this file and collides with any
/// other module that does the same.
struct SelectedDay: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSinceReferenceDate }
}
