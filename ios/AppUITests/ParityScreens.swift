import XCTest

/// Every screen, in the fictional showcase library, for the Android parity review (D-084). The Android app's
/// ParityScreens walks the same screens by the same identifiers, and Tools/parity-screens puts each pair side by
/// side. Runs only when asked, through `Tools/parity-screens`, so CI never runs it.
@MainActor
final class ParityScreens: XCTestCase {
    private var app: XCUIApplication!
    private var folder: URL!

    override func setUp() async throws {
        guard let path = ProcessInfo.processInfo.environment["PARITY_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_PARITY_DIR to take the parity screenshots")
        }
        folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--fake-capture", "--showcase", "-recorder.hasSeenConsent", "YES", "-models.hasSeenSetup", "YES",
            "-library.sort", "newest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
    }

    private func shoot(_ name: String) throws {
        sleep(1)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }

    /// The shell and Home: the first screen, and the side menu over it.
    func testShell() throws {
        XCTAssertTrue(app.buttons["home.record"].waitForExistence(timeout: 5))
        try shoot("home")
        app.buttons["drawer.toggle"].tapWhenReady()
        sleep(1)
        try shoot("drawer")
        app.buttons["drawer.item.home"].tapWhenReady()
        app.buttons["home.add"].tapWhenReady()
        try shoot("home-add-menu")
    }
}
