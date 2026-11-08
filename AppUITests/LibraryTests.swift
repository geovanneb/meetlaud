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
        app.buttons["drawer.toggle"].tap()
        app.buttons["drawer.item.library"].tap()
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
        app.buttons["home.connect"].tap()
        XCTAssertTrue(text("Quarterly review"))
        app.buttons["event.record"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Quarterly review"].waitForExistence(timeout: 3))
    }

    func testFolderCreation() {
        openLibrary()
        app.buttons["library.newFolder"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeText("Research")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(text("Research"))
    }

    func testSearchFindsANoteAndOpensTheRecording() {
        openLibrary()
        app.buttons["library.search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Pricing")
        XCTAssertTrue(text("Pricing decision"))
    }

    func testTrashListsDeletedRecordingsAndEmpties() {
        openLibrary()
        app.buttons["library.more"].tap()
        app.buttons["Trash"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.trash"].waitForExistence(timeout: 3))
        XCTAssertTrue(text("Old draft"))
        app.buttons["trash.empty"].tap()
        app.sheets.buttons["Empty Trash"].firstMatch.tap()
        XCTAssertTrue(text("Trash is empty"))
    }

    func testSelectingAndMovingToTrash() {
        openLibrary()
        app.buttons["library.more"].tap()
        app.buttons["Select"].tap()
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Product memo")).firstMatch.tap()
        app.buttons["library.trashSelected"].tap()
        XCTAssertFalse(text("Product memo", timeout: 1))
    }

    func testDrawerSearchOpensSearch() {
        app.buttons["drawer.toggle"].tap()
        app.buttons["drawer.search"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.search"].waitForExistence(timeout: 3))
    }

    func testLibraryPassesAccessibilityAudit() throws {
        openLibrary()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "library"
        shot.lifetime = .keepAlways
        add(shot)
        try app.auditAccessibility()
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
        app.buttons["drawer.toggle"].tap()
        app.buttons["drawer.item.library"].tap()
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

        app.buttons["calendar.title"].tap()
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

        app.buttons["calendar.today"].tap()
        app.buttons[meetingDay].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Quarterly review"].waitForExistence(timeout: 3), "A day lists its own meetings")

        app.buttons["calendar.title"].tap()
        let closed = NSPredicate(format: "count == 7")
        let days = app.buttons.matching(identifier: "calendar.day")
        expectation(for: closed, evaluatedWith: days)
        waitForExpectations(timeout: 3)
    }
}
