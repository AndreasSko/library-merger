import XCTest

final class LibraryMergerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchPlaylistConflict(left: String = "base", right: String = "conflict",
                                        largestText: Bool = false) throws -> XCUIApplication {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("LibraryMergerTests/Fixtures")
        let app = XCUIApplication()
        app.launchArguments = ["--playlist-ui-test", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if largestText { app.launchArguments.append("--playlist-ui-test-largest-text") }
        // The simulator and runner share the build host filesystem. These are synthetic,
        // task-owned fixtures, never a user's library or a production import bypass.
        app.launchEnvironment["PLAYLIST_TEST_LEFT"] = fixtures.appendingPathComponent(left + ".jwlibrary").path
        app.launchEnvironment["PLAYLIST_TEST_RIGHT"] = fixtures.appendingPathComponent(right + ".jwlibrary").path
        app.launch()
        let merge = app.buttons["merge-backups"]
        XCTAssertTrue(merge.waitForExistence(timeout: 15))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: merge)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        merge.tap()
        XCTAssertTrue(app.buttons["cancel-conflicts"].waitForExistence(timeout: 15))
        if right == "conflict" { XCTAssertTrue(app.staticTexts["Changed A"].exists) }
        return app
    }

    func testPublicationConflictShowsOnlyChangedActionAndAcceptsRightChoice() throws {
        try assertPublicationConflictAllowsRightChoice(largestText: false)
    }

    func testPublicationConflictLargestAccessibilityTextAllowsRightChoice() throws {
        try assertPublicationConflictAllowsRightChoice(largestText: true)
    }

    private func assertPublicationConflictAllowsRightChoice(largestText: Bool) throws {
        let app = try launchPlaylistConflict(left: "publication-base", right: "publication-action",
                                              largestText: largestText)
        XCTAssertTrue(app.staticTexts["JW Broadcasting—October 2026"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What should happen when this item finishes?"].exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "End action:")).count, 2)
        for unchanged in ["Start trim:", "End trim:", "Duration:", "Accuracy:", "Thumbnail:", "Media type:"] {
            XCTAssertFalse(app.staticTexts[unchanged].exists, "Unchanged setting must be omitted: " + unchanged)
        }
        XCTAssertTrue(app.buttons["Open on jw.org"].exists)
        XCTAssertFalse(app.buttons["continue-conflicts"].isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Publication action choice"
        attachment.lifetime = .keepAlways
        add(attachment)
        let choice = app.staticTexts.matching(identifier: "conflict-right")
            .matching(NSPredicate(format: "label == %@", "Repeat")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        let scroll = app.scrollViews["conflict-scroll"]
        XCTAssertTrue(scroll.exists)
        for _ in 0..<6 {
            if choice.isHittable { break }
            scroll.swipeUp()
        }
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: choice)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed)
        let scrolled = XCTAttachment(screenshot: app.screenshot())
        scrolled.name = largestText ? "Largest text right action reachable" : "Right action reachable"
        scrolled.lifetime = .keepAlways
        add(scrolled)
        choice.tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"),
                                                object: app.buttons["continue-conflicts"])
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        app.buttons["continue-conflicts"].tap()
        XCTAssertTrue(app.buttons["Export"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["cancel-conflicts"].exists)
    }

    func testCancelRetryChooseRightAndExport() throws {
        let app = try launchPlaylistConflict()
        XCTAssertFalse(app.buttons["continue-conflicts"].isEnabled)
        app.buttons["cancel-conflicts"].tap()
        let merge = app.buttons["merge-backups"]
        XCTAssertTrue(merge.waitForExistence(timeout: 5))
        XCTAssertTrue(merge.isEnabled)
        merge.tap()
        XCTAssertTrue(app.buttons["cancel-conflicts"].waitForExistence(timeout: 10))
        let rightChoice = app.staticTexts.matching(identifier: "conflict-right")
            .matching(NSPredicate(format: "label == %@", "Changed A")).firstMatch
        XCTAssertTrue(rightChoice.waitForExistence(timeout: 5))
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"),
                                                 object: rightChoice)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed)
        rightChoice.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"),
                                                 object: app.buttons["continue-conflicts"])
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        app.buttons["continue-conflicts"].tap()
        XCTAssertTrue(app.buttons["Export"].waitForExistence(timeout: 15))
        assertExportSheet(app)
        let close = app.buttons["header.closeButton"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(app.buttons["Export"].waitForExistence(timeout: 5))
        assertExportSheet(app)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Resolved playlist export"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertExportSheet(_ app: XCUIApplication) {
        let export = app.buttons["Export"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: export)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        export.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 10))
        let caption = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "merged")).firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 30), "Share sheet must finish loading the exported backup")
        XCTAssertTrue(caption.label.hasPrefix("merged"), "Share sheet must contain the exported backup")
        recordScreenshot(app, name: "Export share sheet")
    }

    func testDocumentPickerCancelAndReopenKeepsEmptyMergeUsable() throws {
        let app = try launchPlaylistConflict()
        app.buttons["cancel-conflicts"].tap()
        let reset = app.buttons["new-merge"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        for side in ["leftSide", "leftSide", "rightSide"] {
            let select = app.buttons["select-backup-" + side]
            XCTAssertTrue(select.waitForExistence(timeout: 5))
            select.tap()
            let cancel = app.buttons["Cancel"].firstMatch
            let ready = cancel.waitForExistence(timeout: 10)
            recordScreenshot(app, name: "Document picker " + side)
            XCTAssertTrue(ready, "Document picker should respond after presentation")
            cancel.tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                      object: cancel)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
            XCTAssertTrue(select.isHittable)
            XCTAssertFalse(app.buttons["merge-backups"].isEnabled)
            XCTAssertFalse(app.staticTexts["The following error was returned:"].exists)
        }
    }

    private func recordScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNewMergeAfterCancelDoesNotPresentAbandonedConflict() throws {
        let app = try launchPlaylistConflict()
        app.buttons["cancel-conflicts"].tap()
        let reset = app.buttons["new-merge"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        XCTAssertFalse(app.buttons["merge-backups"].isEnabled)
        let reappeared = app.buttons["cancel-conflicts"].waitForExistence(timeout: 2)
        XCTAssertFalse(reappeared, "An abandoned conflict must not appear after New merge")
        XCTAssertFalse(app.buttons["new-merge"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Select Backup").count, 2)
    }
}
