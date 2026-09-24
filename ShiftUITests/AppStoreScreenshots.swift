//
//  AppStoreScreenshots.swift
//  ShiftUITests
//

import XCTest

/// Walks the app and captures the App Store screenshots as test attachments.
///
/// Skipped in ordinary runs. Enable it with `TEST_RUNNER_SHIFT_SCREENSHOTS=1`
/// against a simulator already seeded with a sample month, with parallel
/// testing off — a cloned simulator wouldn't have the seeded data.
final class AppStoreScreenshots: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SHIFT_SCREENSHOTS"] == "1",
            "Screenshot capture only runs when SHIFT_SCREENSHOTS=1."
        )
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        let home = app.buttons["Home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 15), "Home tab missing")
        home.tap()
        settle()
        capture("01-Home", app: app)

        // The two-shift Monday. Matched on parts, since date wording follows
        // the simulator's region.
        let doubleShiftDay = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS 'Monday' AND label CONTAINS 'September' AND label CONTAINS '7' AND label CONTAINS 'work day'"
        )).firstMatch
        XCTAssertTrue(doubleShiftDay.waitForExistence(timeout: 5), "Day cell not found")
        doubleShiftDay.tap()
        settle()
        capture("02-Day", app: app)
        app.buttons["Done"].firstMatch.tap()
        settle()

        app.buttons["New entry"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Entry"].waitForExistence(timeout: 5), "Entry editor missing")
        settle()
        capture("03-NewEntry", app: app)
        app.buttons["Cancel"].firstMatch.tap()
        settle()

        app.buttons["Income"].firstMatch.tap()
        settle()
        capture("04-Income", app: app)
    }

    private func settle() {
        Thread.sleep(forTimeInterval: 1.2)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
