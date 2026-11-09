import XCTest

@MainActor
final class RecorderTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--fake-capture", "-recorder.hasSeenConsent", "YES"]
        app.launch()
    }

    private func startRecording() {
        app.buttons["home.record"].tapWhenReady()
        XCTAssertTrue(app.buttons["recorder.stop"].waitForExistence(timeout: 3))
    }

    func testRecordAndStopSavesARecording() {
        startRecording()
        app.buttons["recorder.flag"].tapWhenReady()
        app.buttons["recorder.stop"].tapWhenReady()
        XCTAssertTrue(app.descendants(matching: .any)["screen.detail"].waitForExistence(timeout: 3))
        // The fake engine writes no audio, so the screen must say so instead of staying blank.
        XCTAssertTrue(app.staticTexts["This recording is unavailable"].waitForExistence(timeout: 3))
    }

    func testMinimizeShowsThePillAndRecordingContinues() {
        startRecording()
        app.buttons["recorder.minimize"].tapWhenReady()
        let pill = app.buttons["recorder.pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 2))
        app.buttons["drawer.toggle"].tapWhenReady()
        app.buttons["drawer.item.library"].tapWhenReady()
        XCTAssertTrue(pill.waitForExistence(timeout: 2), "The pill must stay on every screen")
        pill.tap()
        XCTAssertTrue(app.buttons["recorder.stop"].waitForExistence(timeout: 2))
    }

    func testPauseAndResume() {
        startRecording()
        app.buttons["recorder.pause"].tapWhenReady()
        XCTAssertEqual(app.buttons["recorder.pause"].label, "Resume")
        app.buttons["recorder.pause"].tapWhenReady()
        XCTAssertEqual(app.buttons["recorder.pause"].label, "Pause")
    }

    func testConsentIsShownOnFirstRecording() {
        app.terminate()
        app.launchArguments = ["--fake-capture", "-recorder.hasSeenConsent", "NO"]
        app.launch()
        app.buttons["home.record"].tapWhenReady()
        let accept = app.alerts.buttons["Got it"]
        XCTAssertTrue(accept.waitForExistence(timeout: 2))
        accept.tap()
        XCTAssertTrue(app.buttons["recorder.stop"].waitForExistence(timeout: 3))
    }

    func testRecordURLNeverStartsCapture() throws {
        try app.open(XCTUnwrap(URL(string: "meetlaud://record")))
        XCTAssertTrue(app.buttons["recorder.start"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["recorder.stop"].exists)
    }
}
