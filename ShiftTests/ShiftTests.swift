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

    @Test func workRequiresCompensationAndAPositiveRate() {
        #expect(validate(compensation: nil, hourly: nil).contains(.missingCompensationType))
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

// MARK: - Assistant tool decoding

struct AssistantToolsTests {
    private let timeZone = TimeZone(identifier: "Europe/Madrid")!

    @Test func decodesACreateEventsCall() throws {
        let input: [String: Any] = [
            "events": [
                [
                    "title": "Turno",
                    "type": "work",
                    "start": "2026-09-03T14:30:00",
                    "end": "2026-09-03T19:00:00",
                    "compensation_type": "hourly",
                    "rate_cents": 1250,
                ]
            ]
        ]
        let actions = AssistantTools.actions(toolName: AssistantTools.createEvents, input: input, timeZone: timeZone)
        #expect(actions.count == 1)

        guard case .createEvent(let spec) = try #require(actions.first) else {
            Issue.record("expected a createEvent action")
            return
        }
        #expect(spec.title == "Turno")
        #expect(spec.type == .work)
        #expect(spec.hourlyRateCents == 1250)
        #expect(spec.compensationType == .hourly)
        #expect(spec.validationErrors(resolvedSubject: nil).isEmpty)
    }

    /// A repeating request arrives as many explicit entries, never as a rule.
    @Test func decodesABatchOfOccurrences() {
        let events = (3 ... 6).map { day in
            [
                "title": "Turno",
                "type": "work",
                "start": "2026-09-0\(day)T14:30:00",
                "end": "2026-09-0\(day)T19:00:00",
                "compensation_type": "hourly",
                "rate_cents": 1250,
            ] as [String: Any]
        }
        let actions = AssistantTools.actions(
            toolName: AssistantTools.createEvents,
            input: ["events": events],
            timeZone: timeZone
        )
        #expect(actions.count == 4)
    }

    /// Malformed model output must degrade to "nothing proposed", never to a
    /// corrupt entry.
    @Test func dropsMalformedEvents() {
        let input: [String: Any] = [
            "events": [
                ["title": "No dates", "type": "work"],
                ["title": "Bad type", "type": "nonsense", "start": "2026-09-03T14:30:00", "end": "2026-09-03T19:00:00"],
                ["title": "Inverted", "type": "work", "start": "2026-09-03T19:00:00", "end": "2026-09-03T14:30:00"],
                ["title": "Unparseable", "type": "work", "start": "next Tuesday", "end": "later"],
            ]
        ]
        let actions = AssistantTools.actions(toolName: AssistantTools.createEvents, input: input, timeZone: timeZone)
        #expect(actions.isEmpty)
    }

    @Test func decodesDeletionAndRescheduling() {
        let id = UUID()
        let delete = AssistantTools.actions(
            toolName: AssistantTools.deleteEvent,
            input: ["id": id.uuidString],
            timeZone: timeZone
        )
        #expect(delete.count == 1)
        #expect(delete.first?.isDestructive == true)

        let move = AssistantTools.actions(
            toolName: AssistantTools.rescheduleEvent,
            input: ["id": id.uuidString, "start": "2026-09-05T10:00:00", "end": "2026-09-05T14:00:00"],
            timeZone: timeZone
        )
        #expect(move.count == 1)
        #expect(move.first?.isDestructive == true)
    }

    @Test func rejectsAnUnparseableIdentifier() {
        #expect(AssistantTools.actions(toolName: AssistantTools.deleteEvent, input: ["id": "not-a-uuid"], timeZone: timeZone).isEmpty)
        #expect(AssistantTools.actions(toolName: AssistantTools.deleteEvent, input: [:], timeZone: timeZone).isEmpty)
    }

    @Test func createEventsAreNotDestructive() {
        let actions = AssistantTools.actions(
            toolName: AssistantTools.createEvents,
            input: ["events": [["title": "X", "type": "calendar", "start": "2026-09-03T14:30:00", "end": "2026-09-03T19:00:00"]]],
            timeZone: timeZone
        )
        #expect(actions.first?.isDestructive == false)
    }

    @Test func ignoresUnknownTools() {
        #expect(AssistantTools.actions(toolName: "drop_database", input: [:], timeZone: timeZone).isEmpty)
    }

    @Test func systemPromptCarriesTheGroundingFacts() {
        let context = AssistantContext(
            today: Date(timeIntervalSinceReferenceDate: 0),
            timeZoneIdentifier: "Europe/Madrid",
            localeIdentifier: "es_ES",
            schoolEnabled: false,
            subjectNames: ["Cálculo"],
            presetNames: ["Partido Real Madrid"],
            upcomingEvents: []
        )
        let prompt = AssistantTools.systemPrompt(context: context)
        #expect(prompt.contains("Europe/Madrid"))
        #expect(prompt.contains("disabled"))
        #expect(prompt.contains("Cálculo"))
        #expect(prompt.contains("Partido Real Madrid"))
    }
}

// MARK: - Offline assistant

@MainActor
struct MockAIProviderTests {
    private func context() -> AssistantContext {
        AssistantContext(
            today: Date(),
            timeZoneIdentifier: TimeZone.current.identifier,
            localeIdentifier: "en_GB",
            schoolEnabled: false,
            subjectNames: [],
            presetNames: [],
            upcomingEvents: []
        )
    }

    @Test func proposesAShiftFromPlainLanguage() async throws {
        let reply = try await MockAIProvider().respond(
            to: [AssistantMessage(role: .user, text: "Add a shift Thursday 14:30-19:00 at 12.50/h")],
            context: context()
        )
        let proposal = try #require(reply.proposal)
        #expect(proposal.actions.count == 1)

        guard case .createEvent(let spec) = proposal.actions[0] else {
            Issue.record("expected a createEvent action")
            return
        }
        #expect(spec.hourlyRateCents == 1250)
        #expect(spec.type == .work)
    }

    @Test func expandsARepeatingRequest() async throws {
        let reply = try await MockAIProvider().respond(
            to: [AssistantMessage(role: .user, text: "every monday 9-17")],
            context: context()
        )
        let proposal = try #require(reply.proposal)
        #expect(proposal.actions.count == 4)
        #expect(!proposal.containsDestructive)
    }

    @Test func offersHelpWhenItCannotParse() async throws {
        let reply = try await MockAIProvider().respond(
            to: [AssistantMessage(role: .user, text: "hello there")],
            context: context()
        )
        #expect(reply.proposal == nil)
        #expect(!reply.text.isEmpty)
    }

    /// Demo mode must not silently pretend it deleted something.
    @Test func declinesDeletionsWithoutAKey() async throws {
        let reply = try await MockAIProvider().respond(
            to: [AssistantMessage(role: .user, text: "delete my thursday shift")],
            context: context()
        )
        #expect(reply.proposal == nil)
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
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
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

// MARK: - To-do list

struct TodoStorageTests {
    @Test func entriesAreNonBlankTrimmedLinesInOrder() {
        let text = "Buy milk\n\n   Gym  \n\t\nCall mum\n"
        #expect(TodoStorage.entries(from: text) == ["Buy milk", "Gym", "Call mum"])
    }

    @Test func emptyTextHasNoEntries() {
        #expect(TodoStorage.entries(from: "").isEmpty)
        #expect(TodoStorage.entries(from: "\n \n").isEmpty)
    }
}

struct TodoWidgetLayoutTests {
    private func items(_ count: Int) -> [String] { (1 ... max(1, count)).prefix(count).map { "Item \($0)" } }

    /// Column-major: the left column is filled completely before the right.
    @Test func fillsLeftColumnFirst() {
        let layout = TodoWidgetLayout(entries: items(7), rowsPerColumn: 5)
        #expect(layout.left == (1 ... 5).map { .entry("Item \($0)") })
        #expect(layout.right == [.entry("Item 6"), .entry("Item 7")])
    }

    @Test func exactFitShowsEverythingWithoutOverflow() {
        let layout = TodoWidgetLayout(entries: items(10), rowsPerColumn: 5)
        #expect(layout.left.count == 5)
        #expect(layout.right.count == 5)
        #expect(layout.right.last == .entry("Item 10"))
    }

    /// The bottom-right cell reports what's hidden, and every entry is counted.
    @Test func overflowTakesTheBottomRightCell() {
        let layout = TodoWidgetLayout(entries: items(13), rowsPerColumn: 5)
        #expect(layout.left.count == 5)
        #expect(layout.right.count == 5)
        #expect(layout.right.last == .overflow(4))
        #expect(layout.right.dropLast().last == .entry("Item 9"))
    }

    @Test func emptyInputProducesEmptyColumns() {
        let layout = TodoWidgetLayout(entries: [], rowsPerColumn: 5)
        #expect(layout.left.isEmpty)
        #expect(layout.right.isEmpty)
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
