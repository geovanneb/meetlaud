import XCTest

@MainActor
final class ShellSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--fake-capture"]
        app.launch()
    }

    private func openDrawer() {
        app.buttons["drawer.toggle"].tapWhenReady()
    }

    func testDrawerNavigatesToEveryDestination() {
        for destination in ["library", "ask", "tools", "settings", "help", "home"] {
            openDrawer()
            let item = app.buttons["drawer.item.\(destination)"]
            XCTAssertTrue(item.waitForExistence(timeout: 2), destination)
            item.tap()
            XCTAssertTrue(app.descendants(matching: .any)["screen.\(destination)"].waitForExistence(timeout: 2))
        }
    }

    func testEdgeSwipeOpensTheDrawerAndSwipeBackClosesIt() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        let library = app.buttons["drawer.item.library"]
        XCTAssertTrue(library.waitForExistence(timeout: 2))
        XCTAssertTrue(library.isHittable)

        let open = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        open.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
        XCTAssertTrue(app.buttons["drawer.toggle"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["drawer.toggle"].isHittable)
    }

    /// The drawer watches every sideways drag. It must leave alone the ones it does not use, or a segmented
    /// control can be tapped but not dragged.
    func testDraggingAcrossTabsChangesTheTab() {
        openDrawer()
        app.buttons["drawer.item.tools"].tapWhenReady()
        let tabs = app.segmentedControls["tools.tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 3))
        let first = tabs.buttons.element(boundBy: 0)
        let last = tabs.buttons.element(boundBy: 2)
        XCTAssertTrue(first.isSelected)
        first.press(forDuration: 0.3, thenDragTo: last, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(last.isSelected)
        XCTAssertTrue(app.descendants(matching: .any)["screen.tools"].exists)
    }

    func testTappingOutsideClosesTheDrawer() {
        openDrawer()
        let library = app.buttons["drawer.item.library"]
        XCTAssertTrue(library.waitForExistence(timeout: 2))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "drawer-open"
        shot.lifetime = .keepAlways
        add(shot)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["drawer.toggle"].waitForExistence(timeout: 2))
    }

    /// Without CFBundleLocalizations in the app, iOS ignores package translations, and unit tests cannot see it.
    func testEveryLanguageReachesTheScreen() {
        let expected = ["ja": "会議ノート", "pt-BR": "Notas de reunião", "es": "Notas de reunión", "en": "Meeting notes"]
        for (language, text) in expected {
            app.terminate()
            app.launchArguments = ["--fake-capture", "-AppleLanguages", "(\(language))"]
            app.launch()
            XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 3), language)
        }
    }

    func testDeepLinkOpensSettingsWithoutRecording() throws {
        try app.open(XCTUnwrap(URL(string: "meetlaud://settings/models")))
        XCTAssertTrue(app.descendants(matching: .any)["screen.models"].waitForExistence(timeout: 3))
    }

    /// Home is a long page: with a calendar, upcoming meetings sit above the notes. The audit enlarges text, pushes the
    /// last rows off the screen, and reports that as missing Dynamic Type, so that check runs on its own below.
    func testHomePassesAccessibilityAudit() throws {
        try app.auditAccessibility(for: .all.subtracting(.dynamicType))
    }

    func testHomeWorksAtTheLargestTextSize() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.home"].waitForExistence(timeout: 5))
        // The list builds rows as they come on screen, so the empty state only exists after scrolling to it.
        let empty = app.staticTexts["home.empty"]
        for _ in 0 ..< 8 where !empty.exists {
            app.swipeUp()
        }
        app.reveal(empty)
        XCTAssertTrue(empty.isHittable, "The empty state must stay reachable, under the upcoming meetings")
    }
}
