import XCTest

@MainActor
final class SummaryTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // The default template survives between runs, and one of these tests changes it.
        app.launchArguments = [
            "--fake-capture", "--seed-library", "-recorder.hasSeenConsent", "YES",
            "-summary.defaultTemplate", "builtin.summary",
        ]
        app.launch()
    }

    private func openSummaryTab() {
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Sales meeting")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        let tab = app.segmentedControls.buttons["Summary"]
        XCTAssertTrue(tab.waitForExistence(timeout: 3))
        tab.tap()
    }

    private func generate() {
        let button = app.buttons["summary.generate"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
        XCTAssertTrue(app.staticTexts["Ana opened the meeting"].waitForExistence(timeout: 5))
    }

    func testOneTapMakesASummaryWithEvidence() {
        openSummaryTab()
        generate()
        XCTAssertTrue(app.staticTexts["Key points"].exists)
        XCTAssertTrue(app.buttons["summary.source"].firstMatch.exists, "Claims must link to the audio")
        XCTAssertTrue(
            app.descendants(matching: .any)["summary.review"].firstMatch.exists,
            "A claim with no proof is flagged",
        )
    }

    func testTasksCanBeChecked() {
        openSummaryTab()
        generate()
        let task = app.buttons["summary.task"].firstMatch
        for _ in 0 ..< 4 where !task.exists {
            app.swipeUp()
        }
        XCTAssertTrue(task.waitForExistence(timeout: 3))
        XCTAssertEqual(task.label, "Mark as done")
        task.tap()
        XCTAssertTrue(app.buttons["Mark as not done"].waitForExistence(timeout: 3))
    }

    func testAnotherSummaryOpensInItsOwnTab() {
        openSummaryTab()
        generate()
        app.buttons["summary.add"].tapWhenReady()
        let template = app.buttons["Meeting minutes"]
        XCTAssertTrue(template.waitForExistence(timeout: 3))
        template.tap()
        app.buttons["summary.sheet.generate"].tapWhenReady()
        let tabs = app.buttons.matching(identifier: "summary.tab")
        XCTAssertTrue(tabs.element(boundBy: 1).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Topics discussed"].waitForExistence(timeout: 5))
    }

    func testASummaryIsThereWhenYouComeBack() {
        openSummaryTab()
        generate()
        app.navigationBars.buttons.firstMatch.tapWhenReady()
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Sales meeting")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        XCTAssertTrue(app.staticTexts["Ana opened the meeting"].waitForExistence(timeout: 3), "Opens on the summary")
    }

    func testNoModelLeadsToTheModelsScreen() {
        app.terminate()
        app.launchArguments.append("--no-language-model")
        app.launch()
        openSummaryTab()
        app.buttons["summary.generate"].tapWhenReady()
        XCTAssertTrue(app.descendants(matching: .any)["screen.models"].waitForExistence(timeout: 3))
    }

    private func openTemplates() {
        openTools()
        let tab = app.buttons["Templates"]
        XCTAssertTrue(tab.waitForExistence(timeout: 3))
        tab.tap()
        XCTAssertTrue(app.staticTexts["Meeting minutes"].waitForExistence(timeout: 3))
    }

    private func openTools() {
        app.buttons["drawer.toggle"].tapWhenReady()
        let item = app.buttons["drawer.item.tools"]
        XCTAssertTrue(item.waitForExistence(timeout: 2))
        item.tap()
    }

    func testAConnectorInTheRegistryAppearsInItsTab() throws {
        openTools()
        let tab = app.buttons["Connectors"]
        XCTAssertTrue(tab.waitForExistence(timeout: 3))
        tab.tap()
        let connector = app.buttons["connector.gtd"]
        XCTAssertTrue(connector.waitForExistence(timeout: 3))
        try app.auditAccessibility(for: .all.subtracting(.dynamicType))
        connector.tap()
        let connect = app.buttons["connector.connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 3))
        connect.tap()
        // Its own screen, with everything but audio off until the person says otherwise.
        XCTAssertTrue(app.descendants(matching: .any)["screen.gtd"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.switches["gtd.transcripts"].value as? String, "0")
        XCTAssertEqual(app.switches["gtd.photos"].value as? String, "0")
    }

    func testAFailedPairingSaysWhyAndOffersARetry() throws {
        // A real code for a computer that is not there. The simulator has no camera, so the test supplies it.
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        let secret = Data(repeating: 2, count: 16).base64EncodedString()
        app.terminate()
        app.launchEnvironment["GTD_TEST_CODE"] = """
        {"version":1,"name":"Test Mac","public_key":"\(key)","code":"\(secret)","port":1,"hosts":["127.0.0.1"]}
        """
        app.launch()
        openTools()
        app.buttons["Connectors"].tapWhenReady()
        app.buttons["connector.gtd"].tapWhenReady()
        app.buttons["connector.connect"].tapWhenReady()
        app.buttons["gtd.scan"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["gtd.failed"].waitForExistence(timeout: 10), "A failure must not end in silence")
        XCTAssertTrue(app.buttons["gtd.tryAgain"].exists)
        XCTAssertTrue(app.buttons["gtd.cancel"].exists)
        try app.auditAccessibility(for: [.dynamicType, .sufficientElementDescription, .hitRegion])
    }

    func testTheLibraryShowsBuiltInTemplatesAndSearches() {
        openTemplates()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("lecture")
        XCTAssertTrue(app.staticTexts["Lecture notes"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Meeting minutes"].exists)
    }

    func testATemplateCanBeWrittenByHand() {
        openTemplates()
        app.buttons["templates.add"].tapWhenReady()
        app.buttons["templates.new"].tapWhenReady()
        let name = app.textFields["template.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["template.save"].isEnabled, "An empty template must not save")
        name.tap()
        name.typeText("Sprint review")
        let section = app.textFields["template.section"].firstMatch
        section.tapWhenReady()
        section.typeText("Shipped")
        app.buttons["template.save"].tapWhenReady()
        XCTAssertTrue(app.staticTexts["Sprint review"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["My templates"].exists)
    }

    func testAModelCanDraftATemplate() {
        openTemplates()
        app.buttons["templates.add"].tapWhenReady()
        app.buttons["templates.ai"].tapWhenReady()
        let text = app.textViews["template.ai.description"].exists
            ? app.textViews["template.ai.description"]
            : app.textFields["template.ai.description"]
        XCTAssertTrue(text.waitForExistence(timeout: 3))
        text.tap()
        text.typeText("Sprint reviews")
        app.buttons["template.ai.generate"].tapWhenReady()
        let name = app.textFields["template.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Drafted")
    }

    func testAMindMapOpensFromTheSummary() throws {
        openSummaryTab()
        generate()
        app.buttons["summary.more"].tapWhenReady()
        let open = app.buttons["summary.mindMap"]
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        open.tap()
        let branch = app.buttons["mindmap.branch"].firstMatch
        XCTAssertTrue(branch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["mindmap.leaf"].firstMatch.exists)
        try app.auditAccessibility(for: .all.subtracting([.dynamicType, .contrast]))
        branch.tap()
        XCTAssertTrue(app.buttons["mindmap.branch"].firstMatch.exists)
    }

    func testTheSummaryPassesTheAccessibilityAudit() throws {
        openSummaryTab()
        generate()
        // A long page, with rows cut at the bar. See `auditAccessibility`. The detail audits cover these colors.
        try app.auditAccessibility(for: .all.subtracting([.dynamicType, .contrast]))
    }

    func testTheTemplateLibraryPassesTheAccessibilityAudit() throws {
        openTemplates()
        try app.auditAccessibility()
    }

    func testChoosingADefaultTemplate() {
        openTemplates()
        app.staticTexts["Call notes"].tapWhenReady()
        let more = app.buttons["template.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 3))
        more.tap()
        app.buttons["template.default"].tapWhenReady()
        app.navigationBars.buttons.firstMatch.tapWhenReady()
        XCTAssertTrue(app.staticTexts["Default"].waitForExistence(timeout: 3))
    }
}
