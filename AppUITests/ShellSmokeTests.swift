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
        app.buttons["drawer.toggle"].tap()
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

    func testHomePassesAccessibilityAudit() throws {
        try app.auditAccessibility()
    }
}
