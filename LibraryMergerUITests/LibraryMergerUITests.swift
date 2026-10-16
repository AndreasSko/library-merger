//
//  LibraryMergerUITests.swift
//  LibraryMergerUITests
//
//  Created by Andreas Skorczyk on 11.10.20.
//

import XCTest

class LibraryMergerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPlaylistConflictShowsOnlyChangedSetting() throws {
        let app = launchWithConflict(left: "publication-base", right: "publication-action")
        XCTAssertTrue(app.staticTexts["What should happen when this item finishes?"].exists)
        XCTAssertTrue(app.staticTexts["JW Broadcasting—October 2026"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Open on jw.org"].exists)
        XCTAssertFalse(app.staticTexts["Start trim:"].exists, "Unchanged settings must not be shown")

        chooseRightAndContinue("Repeat", in: app)
    }

    func testPlaylistConflictIsReachableAtLargestTextSize() throws {
        let app = launchWithConflict(left: "publication-base", right: "publication-action",
                                     extraArguments: ["-UIPreferredContentSizeCategoryName",
                                                      "UICTContentSizeCategoryAccessibilityXXXL"])
        chooseRightAndContinue("Repeat", in: app)
    }

    func testCancelAndRetryPlaylistConflict() throws {
        let app = launchWithConflict(left: "base", right: "conflict")
        XCTAssertFalse(app.buttons["continue-conflicts"].isEnabled)
        app.buttons["cancel-conflicts"].tap()

        app.buttons["merge-backups"].tap()
        XCTAssertTrue(app.buttons["cancel-conflicts"].waitForExistence(timeout: 15))
        chooseRightAndContinue("Changed A", in: app)
        app.buttons["Export"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 10))
    }

    private func chooseRightAndContinue(_ label: String, in app: XCUIApplication) {
        let choice = app.staticTexts.matching(identifier: "conflict-right")
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
        for _ in 0..<10 where !choice.isHittable {
            app.swipeUp()
        }
        choice.tap()

        let continueButton = app.buttons["continue-conflicts"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"),
                                                object: continueButton)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed, "Choosing a side enables Continue")
        continueButton.tap()
        XCTAssertTrue(app.buttons["Export"].waitForExistence(timeout: 30))
    }

    private func launchWithConflict(left: String, right: String, extraArguments: [String] = []) -> XCUIApplication {
        // The simulator shares the file system with the test runner, so the app can read the fixtures directly.
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("LibraryMergerTests/Fixtures")
        let app = XCUIApplication()
        app.launchArguments = ["-needsOnboarding", "NO", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            + extraArguments
        app.launchEnvironment["UI_TEST_LEFT_BACKUP"] = fixtures.appendingPathComponent(left + ".jwlibrary").path
        app.launchEnvironment["UI_TEST_RIGHT_BACKUP"] = fixtures.appendingPathComponent(right + ".jwlibrary").path
        app.launch()

        let merge = app.buttons["merge-backups"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: merge)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
        merge.tap()
        XCTAssertTrue(app.buttons["cancel-conflicts"].waitForExistence(timeout: 15))
        return app
    }
}
