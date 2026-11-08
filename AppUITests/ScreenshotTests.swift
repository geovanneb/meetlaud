import XCTest

/// Pictures for the README, from fictional meetings (`--showcase`). Runs only when asked, through
/// `make screenshots`, which also sets the simulator's appearance and a clean status bar.
@MainActor
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private var folder: URL!

    override func setUp() async throws {
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_SCREENSHOT_DIR to take screenshots")
        }
        folder = URL(fileURLWithPath: path)
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--fake-capture", "--showcase", "-recorder.hasSeenConsent", "YES", "-models.hasSeenSetup", "YES",
            "-library.sort", "newest",
        ]
        app.launch()
    }

    /// Only names the files. The Makefile switches the simulator itself, since the app follows the system.
    private var appearance: String {
        ProcessInfo.processInfo.environment["SCREENSHOT_APPEARANCE"] ?? "Light"
    }

    private func shoot(_ name: String) throws {
        sleep(1)
        try XCUIScreen.main.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(name)-\(appearance.lowercased()).png"))
    }

    private func openMeeting() {
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Spring campaign")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.detail"].waitForExistence(timeout: 5))
    }

    func testTakeScreenshots() throws {
        XCTAssertTrue(app.buttons["home.record"].waitForExistence(timeout: 5))
        try shoot("01-home")

        openMeeting()
        app.buttons["Summary"].firstMatch.tap()
        try shoot("03-summary")

        app.buttons["Transcript"].firstMatch.tap()
        XCTAssertTrue(app.buttons["speaker.chip"].firstMatch.waitForExistence(timeout: 5))
        try shoot("02-transcript")

        app.buttons["detail.ask"].tap()
        let suggestion = app.buttons["ask.suggestion"].firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()
        _ = app.buttons["ask.citation"].firstMatch.waitForExistence(timeout: 10)
        try shoot("04-ask")
        app.navigationBars.buttons["BackButton"].firstMatch.tap()
        app.navigationBars.buttons["BackButton"].firstMatch.tap()

        app.buttons["home.record"].tap()
        XCTAssertTrue(app.buttons["recorder.stop"].waitForExistence(timeout: 5))
        sleep(3)
        try shoot("05-recording")
        app.buttons["recorder.stop"].tap()
        sleep(2)

        app.terminate()
        app.launch()
        app.buttons["drawer.toggle"].tap()
        app.buttons["drawer.item.settings"].tap()
        let network = app.buttons["settings.network"]
        app.reveal(network)
        network.tap()
        XCTAssertTrue(app.staticTexts["Nothing has left this device"].waitForExistence(timeout: 5))
        try shoot("06-network")
    }
}
