//
//  ShiftTests.swift
//  ShiftTests
//

import Testing
import Foundation
@testable import Shift

// MARK: - Money

struct MoneyTests {
    @Test func parsesPlainDecimal() {
        #expect(Money.cents(from: "12.50") == 1250)
        #expect(Money.cents(from: "12") == 1200)
        #expect(Money.cents(from: "0.05") == 5)
    }

    /// A Spanish user types a comma; rejecting that would be a real bug.
    @Test func parsesCommaDecimalSeparator() {
        #expect(Money.cents(from: "12,50") == 1250)
        #expect(Money.cents(from: "9,9") == 990)
    }

    @Test func toleratesSurroundingWhitespaceAndSymbol() {
        #expect(Money.cents(from: "  12.50 ") == 1250)
        #expect(Money.cents(from: "12.50\u{00A0}") == 1250)
    }

    /// "1.234" must not be read as €1.23 — better to reject than to misread.
    @Test func rejectsAmbiguousAndInvalidInput() {
        #expect(Money.cents(from: "1.234.5") == nil)
        #expect(Money.cents(from: "") == nil)
        #expect(Money.cents(from: "abc") == nil)
        #expect(Money.cents(from: "-5") == nil)
        #expect(Money.cents(from: "12,50,00") == nil)
    }

    @Test func editableStringRoundTrips() {
        let cents = 1250
        let text = Money.editableString(cents: cents, locale: Locale(identifier: "en_US"))
        #expect(Money.cents(from: text) == cents)
    }
}

// MARK: - Earnings

struct EarningsTests {
    private func event(
        type: EventType = .work,
        compensation: CompensationType? = .hourly,
        hourly: Int? = nil,
        fixed: Int? = nil,
        minutes: Int
    ) -> Event {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        return Event(
            title: "Shift",
            type: type,
            startDate: start,
            endDate: start.addingTimeInterval(TimeInterval(minutes * 60)),
            compensationType: compensation,
            hourlyRateCents: hourly,
            fixedRateCents: fixed
        )
    }

    @Test func hourlyPaysProRata() {
        #expect(event(hourly: 1000, minutes: 60).earningsInCents == 1000)
        #expect(event(hourly: 1000, minutes: 90).earningsInCents == 1500)
        #expect(event(hourly: 1250, minutes: 270).earningsInCents == 5625)
    }

    /// The whole reason rates are integer cents: a naive Double pipeline drifts.
    @Test func hourlyRoundsWithoutFloatingPointDrift() {
        // 20 minutes at €10.00/h is exactly €3.33 after rounding.
        #expect(event(hourly: 1000, minutes: 20).earningsInCents == 333)
        // A month of them must not accumulate error.
        let total = (0 ..< 30).reduce(0) { sum, _ in
            sum + event(hourly: 1000, minutes: 20).earningsInCents
        }
        #expect(total == 9990)
    }

    @Test func fixedRateIgnoresDuration() {
        #expect(event(compensation: .fixed, fixed: 9000, minutes: 60).earningsInCents == 9000)
        #expect(event(compensation: .fixed, fixed: 9000, minutes: 600).earningsInCents == 9000)
    }

    @Test func nonWorkEventsNeverEarn() {
        #expect(event(type: .calendar, hourly: 5000, minutes: 120).earningsInCents == 0)
        #expect(event(type: .school, hourly: 5000, minutes: 120).earningsInCents == 0)
    }

    /// An inverted range must clamp to zero rather than pay negative money.
    @Test func invertedRangeEarnsNothing() {
        let start = Date(timeIntervalSinceReferenceDate: 3600)
        let inverted = Event(
            title: "Bad",
            type: .work,
            startDate: start,
            endDate: start.addingTimeInterval(-3600),
            compensationType: .hourly,
            hourlyRateCents: 1000
        )
        #expect(inverted.durationInMinutes == 0)
        #expect(inverted.earningsInCents == 0)
    }
}

// MARK: - Validation

struct ValidationTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private var end: Date { start.addingTimeInterval(3600) }

    private func validate(
        title: String = "Shift",
        type: EventType = .work,
        end: Date? = nil,
        compensation: CompensationType? = .hourly,
        hourly: Int? = 1000,
        fixed: Int? = nil,
        kind: SchoolEventKind? = nil,
        subject: Subject? = nil,
        notes: String? = nil
    ) -> [Event.ValidationError] {
        Event.validate(
            title: title, type: type, startDate: start, endDate: end ?? self.end,
            compensationType: compensation, hourlyRateCents: hourly, fixedRateCents: fixed,
            schoolKind: kind, subject: subject, notes: notes
        )
    }

    @Test func acceptsAWellFormedWorkEvent() {
        #expect(validate().isEmpty)
    }

    @Test func requiresTitle() {
        #expect(validate(title: "").contains(.missingTitle))
        #expect(validate(title: "   ").contains(.missingTitle))
    }

    /// An exam is named from its subject, so it is the one case with no title.
    @Test func examDoesNotRequireATitle() {
        let subject = Subject(name: "Calculus")
        let errors = validate(
            title: "", type: .school, compensation: nil, hourly: nil,
            kind: .exam, subject: subject
        )
        #expect(!errors.contains(.missingTitle))
        #expect(errors.isEmpty)
    }

    @Test func requiresEndAfterStart() {
        #expect(validate(end: start).contains(.endBeforeStart))
        #expect(validate(end: start.addingTimeInterval(-60)).contains(.endBeforeStart))
    }

    /// Pay is optional — a fixed monthly wage means the shift records time only.
    @Test func workWithoutPayIsValid() {
        #expect(validate(compensation: nil, hourly: nil).isEmpty)
    }

    /// But choosing a rate type and leaving the amount out is still incoherent.
    @Test func aChosenRateTypeStillNeedsAPositiveRate() {
        #expect(validate(hourly: nil).contains(.missingRate))
        #expect(validate(hourly: 0).contains(.nonPositiveRate))
    }

    @Test func schoolRequiresKindAndSubject() {
        let errors = validate(type: .school, compensation: nil, hourly: nil)
        #expect(errors.contains(.missingSchoolKind))
        #expect(errors.contains(.missingSubject))
    }

    /// Calendar entries carry no compensation and must not inherit work's rules.
    @Test func calendarEventNeedsOnlyTitleAndTimes() {
        #expect(validate(type: .calendar, compensation: nil, hourly: nil).isEmpty)
    }

    @Test func notesAreOptionalButCapped() {
        #expect(validate(notes: nil).isEmpty)
        #expect(validate(notes: String(repeating: "a", count: 250)).isEmpty)
        #expect(validate(notes: String(repeating: "a", count: 251)).contains(.notesTooLong))
    }
}

// MARK: - Month grid overflow

struct ChipLayoutTests {
    @Test func showsEverythingWhenItFits() {
        let layout = ChipLayout(total: 3, capacity: 5)
        #expect(layout.visibleCount == 3)
        #expect(layout.overflowCount == 0)
    }

    @Test func showsEverythingAtExactCapacity() {
        let layout = ChipLayout(total: 5, capacity: 5)
        #expect(layout.visibleCount == 5)
        #expect(layout.overflowCount == 0)
    }

    /// The "+N More" line costs a slot, so one extra event hides two.
    @Test func overflowLineConsumesASlot() {
        let layout = ChipLayout(total: 6, capacity: 5)
        #expect(layout.visibleCount == 4)
        #expect(layout.overflowCount == 2)
        #expect(layout.visibleCount + 1 <= 5)
    }

    @Test func everyEventIsAccountedFor() {
        for total in 0 ... 20 {
            for capacity in 0 ... 8 {
                let layout = ChipLayout(total: total, capacity: capacity)
                #expect(layout.visibleCount + layout.overflowCount == total)
                #expect(layout.visibleCount >= 0)
                #expect(layout.overflowCount >= 0)
            }
        }
    }

    @Test func zeroCapacityHidesEverything() {
        let layout = ChipLayout(total: 4, capacity: 0)
        #expect(layout.visibleCount == 0)
        #expect(layout.overflowCount == 4)
    }
}

// MARK: - Recurrence

struct RecurrenceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func generatesEveryMatchingWeekday() {
        // Thursdays in August 2026: 6, 13, 20, 27.
        let occurrences = Recurrence.occurrences(
            start: date(2026, 8, 6, 14, 30),
            end: date(2026, 8, 6, 19, 0),
            weekdays: [5],
            until: date(2026, 8, 31, 23, 59),
            calendar: calendar
        )
        #expect(occurrences.count == 4)
        #expect(occurrences.allSatisfy { calendar.component(.weekday, from: $0.start) == 5 })
        #expect(occurrences.allSatisfy { calendar.component(.hour, from: $0.start) == 14 })
        #expect(occurrences.allSatisfy { calendar.component(.minute, from: $0.start) == 30 })
    }

    @Test func preservesDuration() {
        let occurrences = Recurrence.occurrences(
            start: date(2026, 8, 6, 14, 30),
            end: date(2026, 8, 6, 19, 0),
            weekdays: [5],
            until: date(2026, 8, 31, 23, 59),
            calendar: calendar
        )
        for occurrence in occurrences {
            #expect(occurrence.end.timeIntervalSince(occurrence.start) == 4.5 * 3600)
        }
    }

    @Test func supportsMultipleWeekdays() {
        let occurrences = Recurrence.occurrences(
            start: date(2026, 8, 3, 9, 0),
            end: date(2026, 8, 3, 17, 0),
            weekdays: [2, 4],
            until: date(2026, 8, 16, 23, 59),
            calendar: calendar
        )
        // Mondays 3, 10 and Wednesdays 5, 12.
        #expect(occurrences.count == 4)
    }

    /// Keeping wall-clock time across a DST change is the point of stepping day
    /// by day rather than adding 604800-second intervals.
    @Test func keepsWallClockTimeAcrossDaylightSaving() {
        // Europe/Madrid moves off DST on 25 October 2026.
        let occurrences = Recurrence.occurrences(
            start: date(2026, 10, 19, 9, 0),
            end: date(2026, 10, 19, 17, 0),
            weekdays: [2],
            until: date(2026, 11, 9, 23, 59),
            calendar: calendar
        )
        #expect(occurrences.count == 4)
        #expect(occurrences.allSatisfy { calendar.component(.hour, from: $0.start) == 9 })
    }

    @Test func returnsNothingForAnEmptyOrInvalidRule() {
        let base = date(2026, 8, 6, 14, 30)
        #expect(Recurrence.occurrences(start: base, end: base.addingTimeInterval(3600), weekdays: [], until: date(2026, 8, 31, 0, 0), calendar: calendar).isEmpty)
        // End date before the start date.
        #expect(Recurrence.occurrences(start: base, end: base.addingTimeInterval(3600), weekdays: [5], until: date(2026, 7, 1, 0, 0), calendar: calendar).isEmpty)
        // Zero-length event.
        #expect(Recurrence.occurrences(start: base, end: base, weekdays: [5], until: date(2026, 8, 31, 0, 0), calendar: calendar).isEmpty)
    }

    @Test func respectsTheSafetyLimit() {
        let base = date(2026, 1, 1, 9, 0)
        let occurrences = Recurrence.occurrences(
            start: base,
            end: base.addingTimeInterval(3600),
            weekdays: [1, 2, 3, 4, 5, 6, 7],
            until: date(2030, 1, 1, 0, 0),
            calendar: calendar,
            limit: 50
        )
        #expect(occurrences.count == 50)
    }
}

// MARK: - Month grid

struct CalendarMathTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        calendar.firstWeekday = 2 // Monday, as in Spain
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// The grid is fixed and non-scrolling, so it must always be whole weeks.
    @Test func gridIsAlwaysWholeWeeks() {
        for month in 1 ... 12 {
            let days = CalendarMath.monthGridDays(for: date(2026, month, 15), calendar: calendar)
            #expect(days.count % 7 == 0)
            #expect(days.count >= 28)
        }
    }

    @Test func gridStartsOnTheLocaleFirstWeekday() {
        let days = CalendarMath.monthGridDays(for: date(2026, 8, 15), calendar: calendar)
        #expect(calendar.component(.weekday, from: days[0]) == calendar.firstWeekday)
    }

    @Test func gridCoversTheWholeMonth() {
        let days = CalendarMath.monthGridDays(for: date(2026, 8, 15), calendar: calendar)
        let first = date(2026, 8, 1)
        let last = date(2026, 8, 31)
        #expect(days.contains { calendar.isDate($0, inSameDayAs: first) })
        #expect(days.contains { calendar.isDate($0, inSameDayAs: last) })
    }

    @Test func monthBoundsAreHalfOpen() {
        let start = CalendarMath.startOfMonth(for: date(2026, 8, 15), calendar: calendar)
        let next = CalendarMath.startOfNextMonth(for: date(2026, 8, 15), calendar: calendar)
        #expect(calendar.component(.day, from: start) == 1)
        #expect(calendar.component(.month, from: start) == 8)
        #expect(calendar.component(.day, from: next) == 1)
        #expect(calendar.component(.month, from: next) == 9)
    }

    @Test func steppingWrapsTheYear() {
        let december = CalendarMath.month(byAdding: 1, to: date(2026, 11, 15), calendar: calendar)
        #expect(calendar.component(.month, from: december) == 12)
        let january = CalendarMath.month(byAdding: 1, to: december, calendar: calendar)
        #expect(calendar.component(.month, from: january) == 1)
        #expect(calendar.component(.year, from: january) == 2027)
    }

    @Test func weekdaySymbolsAreRotatedToFirstWeekday() {
        let symbols = CalendarMath.weekdaySymbols(calendar: calendar, locale: Locale(identifier: "es_ES"))
        #expect(symbols.count == 7)
        // firstWeekday 2 is Monday, so the first symbol must not be Sunday's.
        let sundayFirst = CalendarMath.weekdaySymbols(
            calendar: {
                var c = calendar; c.firstWeekday = 1; return c
            }(),
            locale: Locale(identifier: "es_ES")
        )
        #expect(symbols[0] != sundayFirst[0])
    }
}

// MARK: - Recurrence series operations

import SwiftData

@MainActor
struct EventSeriesTests {
    /// In-memory container so each test gets a clean, isolated store.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema([Event.self, Preset.self, Subject.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
        return ModelContext(container)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Builds four weekly occurrences sharing one recurrence group.
    @discardableResult
    private func makeSeries(in context: ModelContext) -> [Event] {
        let groupID = UUID()
        let events = [6, 13, 20, 27].map { day in
            let event = Event(
                title: "Turno jueves",
                type: .work,
                startDate: date(2026, 8, day, 14, 30),
                endDate: date(2026, 8, day, 19, 0),
                compensationType: .hourly,
                hourlyRateCents: 1400,
                isRecurring: true,
                recurrenceID: groupID
            )
            context.insert(event)
            return event
        }
        return events
    }

    @Test func recognisesSeriesMembership() throws {
        let context = try makeContext()
        let series = makeSeries(in: context)

        #expect(EventSeries.hasSiblings(series[0], context: context))
        #expect(EventSeries.siblings(of: series[0], context: context).count == 4)
    }

    /// A one-off entry must not be offered a "whole series" choice.
    @Test func standaloneEntryHasNoSiblings() throws {
        let context = try makeContext()
        let event = Event(title: "One off", type: .calendar,
                          startDate: date(2026, 8, 3, 9, 0), endDate: date(2026, 8, 3, 10, 0))
        context.insert(event)

        #expect(!EventSeries.hasSiblings(event, context: context))
        #expect(EventSeries.siblings(of: event, context: context).count == 1)
    }

    /// A group that ended up with a single member is also not a real series.
    @Test func singleOccurrenceGroupHasNoSiblings() throws {
        let context = try makeContext()
        let event = Event(title: "Lone", type: .calendar,
                          startDate: date(2026, 8, 3, 9, 0), endDate: date(2026, 8, 3, 10, 0),
                          isRecurring: true, recurrenceID: UUID())
        context.insert(event)

        #expect(!EventSeries.hasSiblings(event, context: context))
    }

    @Test func deletingOneOccurrenceLeavesTheRest() throws {
        let context = try makeContext()
        let series = makeSeries(in: context)

        EventSeries.delete(series[0], scope: .thisOccurrence, context: context)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<Event>())
        #expect(remaining.count == 3)
    }

    @Test func deletingTheSeriesRemovesEveryOccurrence() throws {
        let context = try makeContext()
        let series = makeSeries(in: context)

        EventSeries.delete(series[0], scope: .wholeSeries, context: context)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<Event>())
        #expect(remaining.isEmpty)
    }

    /// The point of propagation: details and time of day travel, dates do not.
    @Test func propagationUpdatesDetailsButKeepsEachDate() throws {
        let context = try makeContext()
        let series = makeSeries(in: context)
        let edited = series[0]

        edited.title = "Turno nuevo"
        edited.hourlyRateCents = 1600
        edited.startDate = date(2026, 8, 6, 15, 0)
        edited.endDate = date(2026, 8, 6, 20, 0)

        EventSeries.propagate(from: edited, context: context, calendar: calendar)
        try context.save()

        for sibling in EventSeries.siblings(of: edited, context: context) {
            #expect(sibling.title == "Turno nuevo")
            #expect(sibling.hourlyRateCents == 1600)
            // New time of day, five-hour duration.
            #expect(calendar.component(.hour, from: sibling.startDate) == 15)
            #expect(calendar.component(.minute, from: sibling.startDate) == 0)
            #expect(sibling.endDate.timeIntervalSince(sibling.startDate) == 5 * 3600)
        }

        // Each occurrence stays on its own Thursday.
        let days = EventSeries.siblings(of: edited, context: context)
            .map { calendar.component(.day, from: $0.startDate) }
            .sorted()
        #expect(days == [6, 13, 20, 27])
    }

    /// Changing the type must clear the fields that no longer apply, on every
    /// occurrence — not just the one that was edited.
    @Test func propagationCarriesClearedFields() throws {
        let context = try makeContext()
        let series = makeSeries(in: context)
        let edited = series[0]

        edited.type = .calendar
        edited.compensationType = nil
        edited.hourlyRateCents = nil

        EventSeries.propagate(from: edited, context: context, calendar: calendar)
        try context.save()

        for sibling in EventSeries.siblings(of: edited, context: context) {
            #expect(sibling.type == .calendar)
            #expect(sibling.hourlyRateCents == nil)
            #expect(sibling.earningsInCents == 0)
        }
    }

    @Test func propagationIgnoresUnrelatedEntries() throws {
        let context = try makeContext()
        let series = makeSeries(in: context)

        let unrelated = Event(title: "Otra cosa", type: .calendar,
                              startDate: date(2026, 8, 7, 9, 0), endDate: date(2026, 8, 7, 10, 0))
        context.insert(unrelated)

        series[0].title = "Cambiado"
        EventSeries.propagate(from: series[0], context: context, calendar: calendar)
        try context.save()

        #expect(unrelated.title == "Otra cosa")
    }
}

// MARK: - Month export

@MainActor
struct MonthExporterTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func work(_ title: String, _ start: Date, hours: Int = 2, rate: Int = 1000) -> Event {
        Event(title: title, type: .work, startDate: start,
              endDate: start.addingTimeInterval(TimeInterval(hours * 3600)),
              compensationType: .hourly, hourlyRateCents: rate)
    }

    @Test func groupsByStartMonthAndOrdersChronologically() {
        let events = [
            work("Late", date(2026, 8, 20)),
            work("Early", date(2026, 8, 3)),
            // Starts on 31 July, ends in August: belongs to July, like Income.
            work("Overnight", date(2026, 7, 31, 22), hours: 5),
            work("Elsewhere", date(2026, 9, 1)),
        ]
        let document = MonthExporter.makeDocument(
            events: events, months: [date(2026, 8, 15), date(2026, 7, 1)], calendar: calendar
        )
        #expect(document.months.map(\.month) == ["2026-07", "2026-08"])
        #expect(document.months[0].entries.map(\.title) == ["Overnight"])
        #expect(document.months[1].entries.map(\.title) == ["Early", "Late"])
    }

    @Test func carriesEarningsAndDisplayTitles() {
        let subject = Subject(name: "Calculus")
        let exam = Event(title: "", type: .school, startDate: date(2026, 8, 10),
                         endDate: date(2026, 8, 10, 11), schoolKind: .exam, subject: subject)
        let shift = work("Shift", date(2026, 8, 11), hours: 3, rate: 1250)

        let entries = MonthExporter.makeDocument(events: [exam, shift], months: [date(2026, 8, 1)], calendar: calendar)
            .months[0].entries

        #expect(entries[0].title == "Calculus Exam")
        #expect(entries[0].subject == "Calculus")
        #expect(entries[0].earningsCents == 0)
        #expect(entries[1].earningsCents == 3750)
        #expect(entries[1].durationMinutes == 180)
    }

    @Test func roundTripsThroughJSON() throws {
        let document = MonthExporter.makeDocument(
            events: [work("Shift", date(2026, 8, 3))],
            months: [date(2026, 8, 1)],
            calendar: calendar,
            now: date(2026, 9, 1, 12)
        )
        let data = try MonthExporter.encode(document, timeZone: calendar.timeZone)
        let json = try #require(String(data: data, encoding: .utf8))
        // Times keep the local offset rather than being flattened to UTC.
        #expect(json.contains("+02:00"))
        #expect(try MonthExporter.decode(data) == document)
    }

    @Test func fileNamesDescribeTheRange() {
        #expect(MonthExporter.fileName(for: [date(2026, 8, 9)], calendar: calendar) == "Shift-2026-08.json")
        #expect(MonthExporter.fileName(for: [date(2026, 8, 1), date(2026, 6, 1), date(2026, 7, 1)], calendar: calendar)
                == "Shift-2026-06_to_2026-08.json")
        #expect(MonthExporter.fileName(for: [], calendar: calendar) == "Shift.json")
    }

    @Test func availableMonthsAreNewestFirstWithCounts() {
        let events = [work("A", date(2026, 6, 2)), work("B", date(2026, 8, 2)), work("C", date(2026, 8, 5))]
        let months = MonthExporter.availableMonths(for: events, calendar: calendar)
        #expect(months.map { MonthExporter.monthKey(for: $0.start, calendar: calendar) } == ["2026-08", "2026-06"])
        #expect(months.map(\.entryCount) == [2, 1])
    }
}

// MARK: - Work day summary

@MainActor
struct WorkDaySummaryTests {
    private func event(_ title: String, _ type: EventType, recurring: Bool = false) -> Event {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        return Event(
            title: title, type: type, startDate: start,
            endDate: start.addingTimeInterval(3600), isRecurring: recurring
        )
    }

    @Test func aDayWithoutWorkHasNoHeadline() {
        let summary = WorkDaySummary(events: [event("Dentist", .calendar), event("Exam prep", .school)])
        #expect(!summary.isWorkDay)
        #expect(summary.headline == nil)
        #expect(summary.otherEvents.count == 2)
        #expect(summary.leadEvent == nil)
    }

    /// One shift names the day; school and calendar entries stay as chips.
    @Test func oneShiftNamesTheDay() {
        let summary = WorkDaySummary(events: [event("Bar Central", .work), event("Gym", .calendar)])
        #expect(summary.isWorkDay)
        #expect(summary.headline == "Bar Central")
        #expect(summary.workEvents.count == 1)
        #expect(summary.otherEvents.map(\.displayTitle) == ["Gym"])
    }

    /// Two titles would truncate to noise in a box this small, so it counts.
    @Test func severalShiftsCollapseToACount() throws {
        let summary = WorkDaySummary(events: [event("Morning", .work), event("Evening", .work)])
        let headline = try #require(summary.headline)
        #expect(headline.contains("2"))
        #expect(headline != "Morning")
        #expect(summary.otherEvents.isEmpty)
    }

    /// A count has no single entry to hang a recurrence marker on.
    @Test func theRecurrenceMarkerIsOnlyForASingleShift() {
        #expect(WorkDaySummary(events: [event("Thursday", .work, recurring: true)]).showsRecurrenceMarker)
        #expect(!WorkDaySummary(events: [event("A", .work, recurring: true), event("B", .work, recurring: true)]).showsRecurrenceMarker)
        #expect(!WorkDaySummary(events: [event("One off", .work)]).showsRecurrenceMarker)
    }
}

// MARK: - Income totals

@MainActor
struct MonthIncomeSummaryTests {
    private func shift(minutes: Int, rate: Int?) -> Event {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        return Event(
            title: "Shift", type: .work, startDate: start,
            endDate: start.addingTimeInterval(TimeInterval(minutes * 60)),
            compensationType: rate == nil ? nil : .hourly,
            hourlyRateCents: rate
        )
    }

    /// An unpaid shift is still worked time — it just earns nothing.
    @Test func unpaidShiftsAddHoursButNoMoney() {
        let summary = MonthIncomeSummary(workEvents: [shift(minutes: 120, rate: 1000), shift(minutes: 60, rate: nil)])
        #expect(summary.totalCents == 2000)
        #expect(summary.totalMinutes == 180)
        #expect(summary.paidMinutes == 120)
        #expect(summary.shiftCount == 2)
    }

    /// Averaging over unpaid time would report €1.54/h for €10/h work.
    @Test func theAverageIgnoresUnpaidTime() {
        let summary = MonthIncomeSummary(workEvents: [shift(minutes: 60, rate: 1000), shift(minutes: 600, rate: nil)])
        #expect(summary.averageHourlyCents == 1000)
    }

    @Test func aMonthOfUnpaidWorkTotalsZeroWithoutDividingByZero() {
        let summary = MonthIncomeSummary(workEvents: [shift(minutes: 300, rate: nil)])
        #expect(summary.totalCents == 0)
        #expect(summary.averageHourlyCents == nil)
        #expect(summary.totalHours == 5)
    }

    @Test func anEmptyMonthIsAllZeroes() {
        let summary = MonthIncomeSummary(workEvents: [])
        #expect(summary.totalCents == 0)
        #expect(summary.shiftCount == 0)
        #expect(summary.averageHourlyCents == nil)
    }
}

// MARK: - Quick add parsing

struct QuickAddParserTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    /// A Wednesday, so "thursday" resolves to the next day and the maths is
    /// checkable by hand.
    private var now: Date {
        DateComponents(
            calendar: calendar, timeZone: TimeZone(identifier: "Europe/Madrid"),
            year: 2026, month: 9, day: 16, hour: 10
        ).date!
    }

    private func parse(_ text: String) -> QuickAddParser.Result? {
        QuickAddParser.parse(text, calendar: calendar, timeZone: TimeZone(identifier: "Europe/Madrid")!, now: now)
    }

    @Test func readsAShiftWithAWeekdayAndRate() throws {
        let result = try #require(parse("work thursday 9-17 at 12.50/h"))
        #expect(result.type == .work)
        #expect(result.hourlyRateCents == 1250)
        #expect(calendar.component(.weekday, from: result.startDate) == 5)
        #expect(calendar.component(.hour, from: result.startDate) == 9)
        #expect(calendar.component(.hour, from: result.endDate) == 17)
    }

    @Test func readsSpanish() throws {
        let result = try #require(parse("turno jueves de 9 a 17 a 12,50 €/hora"))
        #expect(result.type == .work)
        #expect(result.hourlyRateCents == 1250)
        #expect(calendar.component(.weekday, from: result.startDate) == 5)
    }

    /// No rate and no work word is an ordinary calendar entry, not a shift.
    @Test func withoutARateItIsACalendarEntry() throws {
        let result = try #require(parse("dentist tomorrow 10:30-11:00"))
        #expect(result.type == .calendar)
        #expect(result.hourlyRateCents == nil)
        #expect(calendar.component(.day, from: result.startDate) == 17)
        #expect(calendar.component(.minute, from: result.startDate) == 30)
    }

    @Test func recognisesARepeatingRequest() throws {
        let result = try #require(parse("every monday 9-17"))
        #expect(result.repeatsOnWeekday == 2)
    }

    @Test func aOneOffDoesNotRepeat() throws {
        #expect(try #require(parse("monday 9-17")).repeatsOnWeekday == nil)
    }

    /// An end before the start means the shift crosses midnight.
    @Test func handlesAnOvernightShift() throws {
        let result = try #require(parse("work 22-06"))
        #expect(result.endDate > result.startDate)
        #expect(result.endDate.timeIntervalSince(result.startDate) == 8 * 3600)
    }

    /// Without a time there is nothing to anchor an entry on, so the form is
    /// left alone rather than being filled with an invented time.
    @Test func returnsNothingWithoutATimeRange() {
        #expect(parse("add a shift sometime next week") == nil)
        #expect(parse("") == nil)
    }

    @Test func titleFallsBackWhenOnlySchedulingWordsRemain() throws {
        #expect(try #require(parse("thursday 9-17")).title == "Event")
    }

    @Test func keepsTheNameItWasGiven() throws {
        #expect(try #require(parse("dentist tomorrow 10-11")).title == "Dentist")
    }
}
