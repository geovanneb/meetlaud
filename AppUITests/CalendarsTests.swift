import XCTest

@MainActor
final class CalendarsTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--fake-capture", "--two-calendars"]
        app.launch()
    }

    /// From a pushed screen, back to the top first: only there does the drawer button show.
    private func open(_ item: String) {
        for _ in 0 ..< 3 where !app.buttons["drawer.toggle"].exists {
            app.navigationBars.buttons.firstMatch.tap()
        }
        app.buttons["drawer.toggle"].tap()
        app.buttons["drawer.item.\(item)"].tap()
    }

    private func openCalendarSettings() {
        open("settings")
        app.buttons["settings.calendars"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.calendars"].waitForExistence(timeout: 3))
    }

    private func text(_ value: String) -> XCUIElement {
        app.staticTexts[value]
    }

    func testAPersonalCalendarCanBeLeftOutAndCalendarsTurnedOff() {
        app.buttons["home.connect"].tap()
        XCTAssertTrue(text("Quarterly review").waitForExistence(timeout: 3))
        XCTAssertTrue(text("Piano lesson").exists)

        openCalendarSettings()
        XCTAssertTrue(text("Exchange").exists, "Calendars are grouped by account")
        let personal = app.switches["calendars.item.personal"]
        XCTAssertTrue(personal.waitForExistence(timeout: 3))
        personal.switches.firstMatch.tap()

        open("home")
        XCTAssertTrue(text("Quarterly review").waitForExistence(timeout: 3))
        XCTAssertFalse(text("Piano lesson").exists, "A calendar that is off shows nothing")

        openCalendarSettings()
        app.switches["calendars.use"].switches.firstMatch.tap()
        XCTAssertTrue(app.switches["calendars.item.work"].waitForNonExistence(timeout: 3))

        open("home")
        let off = app.buttons["home.calendarsOff"]
        XCTAssertTrue(off.waitForExistence(timeout: 3), "Turned off on purpose: no Connect card, one quiet line")
        XCTAssertFalse(app.buttons["home.connect"].exists)
        XCTAssertFalse(text("Quarterly review").exists)
    }

    func testTheConnectCardCanBeClosedAndCalendarsConnectedLaterInSettings() {
        XCTAssertTrue(app.buttons["home.connect"].waitForExistence(timeout: 3))
        app.buttons["home.connect.hide"].tap()
        let off = app.buttons["home.calendarsOff"]
        XCTAssertTrue(off.waitForExistence(timeout: 3), "A quiet line says where to connect later")
        XCTAssertFalse(app.buttons["home.connect"].exists)

        off.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.calendars"].waitForExistence(timeout: 3))
        app.switches["calendars.use"].switches.firstMatch.tap()
        XCTAssertTrue(app.switches["calendars.item.work"].waitForExistence(timeout: 3))

        open("home")
        XCTAssertTrue(text("Quarterly review").waitForExistence(timeout: 3))
    }

    func testCalendarsPassAccessibilityAudit() throws {
        app.buttons["home.connect"].tap()
        openCalendarSettings()
        XCTAssertTrue(app.switches["calendars.item.work"].waitForExistence(timeout: 3))
        // A long page: Dynamic Type is checked at the largest size below, as in `SystemTests`.
        try app.auditAccessibility(for: .all.subtracting(.dynamicType))
    }

    func testCalendarsWorkAtTheLargestTextSize() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["home.connect"].tap()
        openCalendarSettings()
        // Rows below the screen do not exist until the list scrolls to them.
        let personal = app.switches["calendars.item.personal"]
        for _ in 0 ..< 8 where !(personal.exists && personal.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(personal.isHittable, "Every calendar must stay reachable")
        personal.switches.firstMatch.tap()
        XCTAssertEqual(personal.value as? String, "0")
    }
}
