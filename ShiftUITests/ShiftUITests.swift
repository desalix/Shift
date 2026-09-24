//
//  ShiftUITests.swift
//  ShiftUITests
//

import XCTest

final class ShiftUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Walks every tab, asserting the shell renders and capturing a screenshot
    /// of each so layout regressions are visible in the test report.
    @MainActor
    func testEachTabRenders() throws {
        let app = XCUIApplication()
        app.launch()

        // The seeded simulator has already been through onboarding; if this run
        // starts fresh, get past it first.
        let getStarted = app.buttons["Get Started"]
        if getStarted.waitForExistence(timeout: 5) {
            getStarted.tap()
        }

        for name in ["Home", "Income", "Settings"] {
            let tab = app.buttons[name]
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "\(name) tab is missing")
            tab.tap()

            // The top bar always shows the current tab's title.
            XCTAssertTrue(
                app.staticTexts[name].waitForExistence(timeout: 5),
                "\(name) title did not appear in the top bar"
            )

            attachScreenshot(named: name)
        }
    }

    /// The month stepper only exists on the month-scoped tabs, and must move the
    /// displayed month rather than the whole app.
    @MainActor
    func testMonthStepperOnlyAppearsOnMonthScopedTabs() throws {
        let app = XCUIApplication()
        app.launch()

        let getStarted = app.buttons["Get Started"]
        if getStarted.waitForExistence(timeout: 5) { getStarted.tap() }

        let next = app.buttons["Next month"]
        let previous = app.buttons["Previous month"]

        XCTAssertTrue(next.waitForExistence(timeout: 10), "Home should have a month stepper")

        next.tap()
        previous.tap()

        app.buttons["Settings"].tap()
        XCTAssertTrue(
            app.staticTexts["Settings"].waitForExistence(timeout: 5),
            "Settings did not appear"
        )
        XCTAssertFalse(next.exists, "Settings must not show a month stepper")

        app.buttons["Income"].tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5), "Income should have a month stepper")
    }

    /// The add button is Home-only, and opens the entry editor.
    @MainActor
    func testAddButtonOpensTheEditor() throws {
        let app = XCUIApplication()
        app.launch()

        let getStarted = app.buttons["Get Started"]
        if getStarted.waitForExistence(timeout: 5) { getStarted.tap() }

        let add = app.buttons["New entry"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Home should have an add button")
        add.tap()

        XCTAssertTrue(
            app.navigationBars["New Entry"].waitForExistence(timeout: 5),
            "The entry editor did not open"
        )
        attachScreenshot(named: "Editor")

        app.buttons["Cancel"].tap()
    }

    // MARK: - Swiping

    /// Swiping the calendar left shows the next month; right comes back.
    @MainActor
    func testSwipingChangesTheMonth() throws {
        let app = launchInUSEnglish()
        let title = app.staticTexts["month-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Home should show the month")
        let start = title.label

        // The pager must open on this month, not the first page it holds.
        let today = DateFormatter()
        today.locale = Locale(identifier: "en_US")
        today.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        let todayCell = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", today.string(from: Date()) + ","))
            .firstMatch
        XCTAssertTrue(todayCell.waitForExistence(timeout: 5), "Today's box should be on screen")
        XCTAssertTrue(todayCell.isHittable, "Today's box should be on the visible page")

        app.windows.firstMatch.swipeLeft()
        XCTAssertTrue(waitForLabel(of: title, toDifferFrom: start), "Swiping left did not change the month")

        app.windows.firstMatch.swipeRight()
        XCTAssertTrue(waitForLabel(of: title, toEqual: start), "Swiping right did not come back")

        // Income pages the same way, even with nothing to list.
        app.buttons["Income"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.windows.firstMatch.swipeLeft()
        XCTAssertTrue(waitForLabel(of: title, toDifferFrom: start), "Swiping Income did not change the month")
    }

    /// In the day sheet, swiping moves to the neighbouring day.
    @MainActor
    func testSwipingChangesTheDay() throws {
        let app = launchInUSEnglish()

        // Day boxes read "<weekday>, <month> <day>, <what's on>"; the sheet
        // is titled with the date part.
        let cell = app.descendants(matching: .any).matching(NSPredicate(
            format: "label ENDSWITH ', no entries' OR label ENDSWITH ', work day' OR label ENDSWITH ' entries' OR label ENDSWITH ' entry'"
        )).element(boundBy: 10)
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "No day box found")
        let dayTitle = String(cell.label[..<cell.label.range(of: ", ", options: .backwards)!.lowerBound])
        cell.tap()

        let firstDay = app.navigationBars[dayTitle]
        XCTAssertTrue(firstDay.waitForExistence(timeout: 5), "Day sheet titled \(dayTitle) did not open")

        // The window, not a list: the neighbouring days' lists exist too,
        // just off screen.
        app.windows.firstMatch.swipeLeft()
        XCTAssertTrue(waitForNonExistence(of: firstDay), "Swiping left did not change the day")

        app.windows.firstMatch.swipeRight()
        XCTAssertTrue(firstDay.waitForExistence(timeout: 5), "Swiping right did not come back")
    }

    // MARK: - 24-hour clock

    /// The US defaults to a 12-hour clock; the entry editor must not.
    @MainActor
    func testEntryTimesUseA24HourClock() throws {
        let app = launchInUSEnglish()
        app.buttons["New entry"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Entry"].waitForExistence(timeout: 5))

        let times = timePickerValues(in: app)
        XCTAssertEqual(times.count, 2, "The start and end times should be on screen")
        for time in times {
            XCTAssertTrue(Self.is24HourTime(time), "Not a 24-hour time in the entry editor: \(time)")
        }
        attachScreenshot(named: "Editor-24h")
    }

    /// A new preset's schedule defaults to 09:00–17:00, which must read "17:00".
    @MainActor
    func testPresetTimesUseA24HourClock() throws {
        let app = launchInUSEnglish()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Settings did not open")
        // The row reads "Manage Presets, <count>".
        let managePresets = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Manage Presets'")).firstMatch
        XCTAssertTrue(managePresets.waitForExistence(timeout: 5))
        managePresets.tap()
        let newPreset = app.buttons["New preset"].firstMatch
        XCTAssertTrue(newPreset.waitForExistence(timeout: 5))
        newPreset.tap()
        XCTAssertTrue(app.navigationBars["New Preset"].waitForExistence(timeout: 5))

        XCTAssertEqual(timePickerValues(in: app), ["09:00", "17:00"], "The preset schedule should read 09:00–17:00")
        attachScreenshot(named: "Preset-24h")
    }

    // MARK: - Settings

    /// General holds language and appearance; School holds the switch, and the
    /// subjects only while it's on. Leaves the switch as it found it.
    @MainActor
    func testSettingsPages() throws {
        let app = launchInUSEnglish()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Settings did not open")

        app.buttons["General"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["General"].waitForExistence(timeout: 5), "General did not open")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Language'")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Theme'")).firstMatch.exists)
        attachScreenshot(named: "Settings-General")
        app.navigationBars["General"].buttons.firstMatch.tap()

        app.buttons["School"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["School"].waitForExistence(timeout: 5), "School did not open")
        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let subjectsField = app.textFields["New subject"]

        func flip() {
            toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
            // Turning off with school data asks first.
            let turnOff = app.buttons["Turn Off"]
            if turnOff.waitForExistence(timeout: 2) { turnOff.tap() }
        }

        if (toggle.value as? String) == "1" {
            XCTAssertTrue(subjectsField.exists, "School is on, so subjects should show")
            attachScreenshot(named: "Settings-School-On")
            flip()
            XCTAssertTrue(subjectsField.waitForNonExistence(timeout: 5), "School off should show nothing else")
            flip()
            XCTAssertTrue(subjectsField.waitForExistence(timeout: 5))
        } else {
            XCTAssertFalse(subjectsField.exists, "School is off, so nothing else should show")
            flip()
            XCTAssertTrue(subjectsField.waitForExistence(timeout: 5), "School on should show subjects")
            attachScreenshot(named: "Settings-School-On")
            flip()
            XCTAssertTrue(subjectsField.waitForNonExistence(timeout: 5))
        }
    }

    // MARK: - Helpers

    /// English in the US region: a 12-hour clock by default, so any 12-hour
    /// time that slips through shows up.
    @MainActor
    private func launchInUSEnglish() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLocale", "en_US", "-AppleLanguages", "(en)"]
        app.launch()
        let getStarted = app.buttons["Get Started"]
        if getStarted.waitForExistence(timeout: 5) { getStarted.tap() }
        return app
    }

    /// The time each picker on screen shows. It's the element's value, not its
    /// label: "09:00" for a time picker, "22:00, Sep 24, 2026" for a date and
    /// time picker — of which only the time is kept.
    private func timePickerValues(in app: XCUIApplication) -> [String] {
        let pickers = app.buttons.matching(NSPredicate(format: "label IN {'Time Picker', 'Date and Time Picker'}"))
        _ = pickers.firstMatch.waitForExistence(timeout: 5)
        return pickers.allElementsBoundByIndex.compactMap { picker in
            (picker.value as? String)?.components(separatedBy: ", ").first
        }
    }

    /// "09:00" or "17:30" — never "9:00 AM" or "5:30 p. m.".
    private static func is24HourTime(_ text: String) -> Bool {
        text.range(of: #"^([01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) != nil
    }

    private func waitForLabel(of element: XCUIElement, toDifferFrom label: String) -> Bool {
        let predicate = NSPredicate(format: "label != %@", label)
        return XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 5) == .completed
    }

    private func waitForLabel(of element: XCUIElement, toEqual label: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 5) == .completed
    }

    private func waitForNonExistence(of element: XCUIElement) -> Bool {
        element.waitForNonExistence(timeout: 5)
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
