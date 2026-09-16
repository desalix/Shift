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

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
