import XCTest

@MainActor
final class AskTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--fake-capture", "--seed-library", "-recorder.hasSeenConsent", "YES"]
        app.launch()
    }

    /// Waits are generous: on a CI machine the first push into a meeting can take more than 3 seconds, and the test
    /// failed there while still on Home. Locally each step takes well under a second.
    private func openMeetingChat() {
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Sales meeting")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let ask = app.buttons["detail.ask"]
        XCTAssertTrue(ask.waitForExistence(timeout: 10))
        ask.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ask.chat"].waitForExistence(timeout: 10))
    }

    func testAMeetingAnswerOpensTheAudioAtItsSource() {
        openMeetingChat()
        let suggestion = app.buttons["ask.suggestion"].firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 3))
        suggestion.tap()

        let citation = app.buttons["ask.citation"].firstMatch
        XCTAssertTrue(citation.waitForExistence(timeout: 5), "Every answer must point at its source")
        citation.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.detail"].waitForExistence(timeout: 3))
    }

    func testRememberingNeedsNoModelAndAppearsInMemory() {
        openMeetingChat()
        let prompt = app.textFields["ask.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        prompt.tap()
        prompt.typeText("Remember that Ana leads sales")
        app.buttons["ask.send"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["Saved to memory: Ana leads sales"].waitForExistence(timeout: 3))
    }

    func testASkillStartsAChatThatFollowsIt() {
        app.buttons["drawer.toggle"].tapWhenReady()
        app.buttons["drawer.item.tools"].tapWhenReady()
        let use = app.buttons["skill.use"].firstMatch
        XCTAssertTrue(use.waitForExistence(timeout: 3))
        use.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ask.skill"].waitForExistence(timeout: 3))
    }

    func testTheChatPassesTheAccessibilityAudit() throws {
        openMeetingChat()
        XCTAssertTrue(app.buttons["ask.suggestion"].firstMatch.waitForExistence(timeout: 3))
        try app.auditAccessibility()
        app.buttons["ask.suggestion"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.buttons["ask.citation"].firstMatch.waitForExistence(timeout: 5))
        try app.auditAccessibility()
    }

    func testAChatCanBeRenamedAndDeleted() {
        openAskFromHome()
        let prompt = app.textFields["ask.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        prompt.tap()
        prompt.typeText("Remember that Ana leads sales")
        app.buttons["ask.send"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["Saved to memory: Ana leads sales"].waitForExistence(timeout: 3))
        app.buttons["ask.history"].tapWhenReady()

        let row = app.buttons["ask.conversation"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.swipeLeft()
        app.buttons["Rename"].firstMatch.tapWhenReady()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.clearAndType("Sales lead")
        app.alerts.buttons["Save"].tapWhenReady()
        // The row is one button, so its text is part of the button's label.
        let renamed = NSPredicate(format: "label CONTAINS %@", "Sales lead")
        XCTAssertTrue(app.buttons.matching(renamed).firstMatch.waitForExistence(timeout: 3))

        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.staticTexts["Ask your meetings"].waitForExistence(timeout: 3))
    }

    func testMemoryCanBeAddedAndDeleted() {
        app.buttons["drawer.toggle"].tapWhenReady()
        app.buttons["drawer.item.settings"].tapWhenReady()
        app.buttons["settings.preferences"].tapWhenReady()
        let open = app.buttons["preferences.memory"]
        for _ in 0 ..< 4 where !open.isHittable {
            app.swipeUp()
        }
        open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.memory"].waitForExistence(timeout: 3))

        app.buttons["memory.add"].tapWhenReady()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("Ana leads sales")
        app.alerts.buttons["Save"].tapWhenReady()
        let item = app.buttons["memory.item"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3))

        item.swipeLeft()
        app.buttons["Delete"].firstMatch.tapWhenReady()
        XCTAssertFalse(item.waitForExistence(timeout: 1))
    }

    func testEmptyHistoryAtLargestTextSizeKeepsComposerReachable() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["drawer.toggle"].tapWhenReady()
        app.buttons["drawer.item.ask"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["Ask your meetings"].waitForExistence(timeout: 5))
        let prompt = app.textFields["ask.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        XCTAssertTrue(prompt.isHittable)
    }

    func testAskOpensFromHome() {
        openAskFromHome()
        XCTAssertTrue(app.descendants(matching: .any)["screen.ask"].exists)
    }

    private func openAskFromHome() {
        let bar = app.buttons["prompt.bar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 3))
        bar.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.ask"].waitForExistence(timeout: 3))
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        let existing = (value as? String) ?? ""
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        typeText(text)
    }
}
