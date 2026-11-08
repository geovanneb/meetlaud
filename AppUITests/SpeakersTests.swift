import XCTest

@MainActor
final class SpeakersTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--fake-capture", "--seed-library", "-recorder.hasSeenConsent", "YES"]
        app.launch()
    }

    private func openTranscript() {
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Sales meeting")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        XCTAssertTrue(app.buttons["speaker.chip"].firstMatch.waitForExistence(timeout: 3))
    }

    private func openFirstSpeaker() {
        app.buttons["speaker.chip"].firstMatch.tap()
        XCTAssertTrue(app.textFields["speaker.name"].waitForExistence(timeout: 3))
    }

    private func chip(_ name: String) -> XCUIElement {
        app.buttons.matching(identifier: "speaker.chip").matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    private func setName(_ name: String) {
        let field = app.textFields["speaker.name"]
        field.tap()
        field.typeText(name)
    }

    func testTranscriptShowsSpeakersByNumber() {
        openTranscript()
        XCTAssertTrue(chip("Speaker 1").exists)
        XCTAssertTrue(chip("Speaker 2").exists)
    }

    func testRenamingASpeaker() {
        openTranscript()
        openFirstSpeaker()
        setName("Ana")
        app.buttons["speaker.save"].tap()
        XCTAssertTrue(chip("Ana").waitForExistence(timeout: 3))
    }

    func testSavingAVoiceAsksForConsentAndAppearsInPeople() {
        openTranscript()
        openFirstSpeaker()
        setName("Ana")
        app.switches["speaker.saveVoice"].switches.firstMatch.tap()
        app.buttons["speaker.save"].tap()
        let consent = app.alerts.buttons["I have their consent"].firstMatch
        XCTAssertTrue(consent.waitForExistence(timeout: 3), "Saving a voice must never skip consent")
        consent.tap()
        XCTAssertTrue(chip("Ana").waitForExistence(timeout: 3))

        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["drawer.toggle"].tap()
        app.buttons["drawer.item.settings"].tapWhenReady()
        app.buttons["settings.people"].tap()
        XCTAssertTrue(app.staticTexts["Ana"].waitForExistence(timeout: 3))
    }

    func testPeopleStartsEmpty() {
        app.buttons["drawer.toggle"].tap()
        app.buttons["drawer.item.settings"].tapWhenReady()
        app.buttons["settings.people"].tap()
        XCTAssertTrue(app.staticTexts["No saved voices"].waitForExistence(timeout: 3))
    }

    func testDetailPassesAccessibilityAudit() throws {
        openTranscript()
        try app.auditAccessibility()
    }
}
