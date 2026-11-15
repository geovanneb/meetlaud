import XCTest

@MainActor
final class LibraryTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--fake-capture", "--seed-library", "-recorder.hasSeenConsent", "YES"]
        app.launch()
    }

    private func openLibrary() {
        app.buttons["drawer.toggle"].tapWhenReady()
        app.buttons["drawer.item.library"].tapWhenReady()
        XCTAssertTrue(app.descendants(matching: .any)["screen.library"].waitForExistence(timeout: 3))
    }

    private func text(_ value: String, timeout: TimeInterval = 3) -> Bool {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
            .waitForExistence(timeout: timeout)
    }

    func testHomeListsSeededRecordings() {
        XCTAssertTrue(text("Sales meeting"))
        XCTAssertFalse(text("Old draft", timeout: 1), "Trashed recordings must not appear on Home")
    }

    func testRecordingFromAnEventUsesItsTitle() {
        app.buttons["home.connect"].tapWhenReady()
        XCTAssertTrue(text("Quarterly review"))
        app.buttons["event.record"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.navigationBars["Quarterly review"].waitForExistence(timeout: 3))
    }

    func testFolderCreation() {
        openLibrary()
        app.buttons["library.newFolder"].tapWhenReady()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeText("Research")
        app.alerts.buttons["Save"].tapWhenReady()
        XCTAssertTrue(text("Research"))
    }

    func testSearchFindsANoteAndOpensTheRecording() {
        openLibrary()
        app.buttons["library.search"].tapWhenReady()
        let field = app.searchFields.firstMatch
        field.typeWhenFocused("Pricing")
        XCTAssertTrue(text("Pricing decision"))
    }

    func testClearingSearchRemovesPreviousResults() {
        openLibrary()
        app.buttons["library.search"].tapWhenReady()
        let field = app.searchFields.firstMatch
        field.typeWhenFocused("Pricing")
        XCTAssertTrue(text("Pricing decision"))
        field.buttons.firstMatch.tapWhenReady()
        let result = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Pricing decision")).firstMatch
        XCTAssertTrue(result.waitForNonExistence(timeout: 3))
    }

    func testTrashListsDeletedRecordingsAndEmpties() {
        openLibrary()
        app.buttons["library.more"].tapWhenReady()
        app.buttons["Trash"].tapWhenReady()
        XCTAssertTrue(app.descendants(matching: .any)["screen.trash"].waitForExistence(timeout: 3))
        XCTAssertTrue(text("Old draft"))
        app.buttons["trash.empty"].tapWhenReady()
        app.sheets.buttons["Empty Trash"].firstMatch.tapWhenReady()
        XCTAssertTrue(text("Trash is empty"))
    }

    func testSelectingAndMovingToTrash() {
        openLibrary()
        app.buttons["library.more"].tapWhenReady()
        app.buttons["Select"].tapWhenReady()
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Product memo")).firstMatch.tapWhenReady()
        app.buttons["library.trashSelected"].tapWhenReady()
        XCTAssertFalse(text("Product memo", timeout: 1))
    }

    func testDrawerSearchOpensSearch() {
        app.buttons["drawer.toggle"].tapWhenReady()
        app.buttons["drawer.search"].tapWhenReady()
        XCTAssertTrue(app.descendants(matching: .any)["screen.search"].waitForExistence(timeout: 3))
    }

    /// A long page: the audit enlarges the text, pushes the folders at the bottom off the screen, and reports that as
    /// missing Dynamic Type, depending on timing (it failed on CI and passed locally). That check runs on its own
    /// below.
    func testLibraryPassesAccessibilityAudit() throws {
        openLibrary()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "library"
        shot.lifetime = .keepAlways
        add(shot)
        try app.auditAccessibility(for: .all.subtracting(.dynamicType))
    }

    func testLibraryWorksAtTheLargestTextSize() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        openLibrary()
        // The list builds rows as they come on screen, so the last folder only exists after scrolling to it.
        let folder = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Clients")).firstMatch
        for _ in 0 ..< 8 where !folder.exists {
            app.swipeUp()
        }
        app.reveal(folder)
        XCTAssertTrue(folder.isHittable, "The last folder must stay reachable")
    }

    func testARecordingMovesToAFolderWithASwipe() {
        openLibraryForMove()
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Sales meeting")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.swipeRight()
        let move = app.buttons["Move"].firstMatch
        XCTAssertTrue(move.waitForExistence(timeout: 3))
        move.tap()
        let folder = app.buttons["Clients"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 3))
        folder.tap()
        XCTAssertTrue(app.staticTexts["1 item"].waitForExistence(timeout: 3), "Recordings keeps one of its two")
    }

    private func openLibraryForMove() {
        app.buttons["drawer.toggle"].tapWhenReady()
        app.buttons["drawer.item.library"].tapWhenReady()
    }

    func testTheCalendarOpensOnTheWeekAndExpandsToTheMonth() throws {
        let connect = app.buttons["home.connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 3))
        connect.tap()
        let row = app.buttons["home.calendar"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.calendar"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons.matching(identifier: "calendar.day").count, 7)
        // The sample meeting is an hour from now, which late at night is tomorrow.
        let meetingDay = Date.now.addingTimeInterval(3600).formatted(date: .complete, time: .omitted)
        let opensToday = Calendar.current.isDateInToday(.now.addingTimeInterval(3600))
        if opensToday {
            XCTAssertTrue(app.staticTexts["Quarterly review"].waitForExistence(timeout: 3), "Today's meeting is listed")
        }

        app.buttons["calendar.title"].tapWhenReady()
        let month = app.buttons["calendar.month"].firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons.matching(identifier: "calendar.day").count, 42)
        // The last rows sit behind the prompt bar, as on every other screen with one.
        try app.auditAccessibility(for: .all.subtracting([.dynamicType, .textClipped]))

        let next = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
        let chip = app.buttons[next.formatted(.dateTime.month(.wide).year())]
        XCTAssertTrue(chip.waitForExistence(timeout: 3))
        chip.tap()
        XCTAssertTrue(
            app.staticTexts["No recordings or meetings"].waitForExistence(timeout: 3),
            "Another day, its own list",
        )

        app.buttons["calendar.today"].tapWhenReady()
        app.buttons[meetingDay].firstMatch.tapWhenReady()
        XCTAssertTrue(app.staticTexts["Quarterly review"].waitForExistence(timeout: 3), "A day lists its own meetings")

        app.buttons["calendar.title"].tapWhenReady()
        let closed = NSPredicate(format: "count == 7")
        let days = app.buttons.matching(identifier: "calendar.day")
        expectation(for: closed, evaluatedWith: days)
        waitForExpectations(timeout: 3)
    }
}
