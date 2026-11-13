import XCTest

/// The iPad has a sidebar instead of the drawer, so it needs its own way around. Skipped on iPhone.
@MainActor
final class IPadTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad layout")
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--fake-capture", "--seed-library", "-recorder.hasSeenConsent", "YES"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func select(_ destination: String) {
        let item = app.buttons["drawer.item.\(destination)"]
        if !item.waitForExistence(timeout: 2) {
            app.buttons["ToggleSidebar"].firstMatch.tapWhenReady()
        }
        XCTAssertTrue(item.waitForExistence(timeout: 3), destination)
        item.tap()
    }

    func testEveryDestinationOpens() {
        for (item, screen) in [
            ("library", "screen.library"), ("ask", "screen.ask"), ("settings", "screen.settings"), (
                "help",
                "screen.help",
            ),
        ] {
            select(item)
            XCTAssertTrue(app.descendants(matching: .any)[screen].waitForExistence(timeout: 3), item)
        }
    }

    func testAMeetingOpensBesideTheListThatStaysInPlace() {
        select("library")
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Sales meeting")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.detail"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["screen.library"].exists, "The list must stay on screen")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "ipad-columns"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSettingsOpenInTheNextColumn() {
        select("settings")
        // In landscape the list is longer than the screen, and a row below the fold does not exist yet.
        let about = app.buttons["settings.about"]
        let list = app.descendants(matching: .any)["screen.settings"]
        for _ in 0 ..< 6 where !about.isHittable {
            list.swipeUp()
        }
        about.tapWhenReady()
        XCTAssertTrue(app.descendants(matching: .any)["screen.about"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].exists)
    }

    func testKeyboardShortcutOpensSearch() {
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["screen.search"].waitForExistence(timeout: 3))
    }
}
