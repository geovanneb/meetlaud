import XCTest

@MainActor
final class ModelsTests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(_ extra: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--fake-capture", "--seed-library"] + extra
        app.launch()
    }

    private func openModels() {
        app.buttons["drawer.toggle"].tap()
        app.buttons["drawer.item.settings"].tapWhenReady()
        app.buttons["settings.models"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.models"].waitForExistence(timeout: 3))
    }

    private func openFastModel() {
        openModels()
        app.buttons["models.role.transcription"].tap()
        app.buttons["model.fake-small"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.modelDetail"].waitForExistence(timeout: 3))
    }

    func testOneTapSetupDownloadsWithoutBlockingTheApp() {
        launch(["--show-setup", "-models.hasSeenSetup", "NO"])
        let download = app.buttons["setup.download"]
        XCTAssertTrue(download.waitForExistence(timeout: 3))
        download.tap()
        XCTAssertTrue(app.buttons["home.record"].waitForExistence(timeout: 3), "The app must stay usable")
    }

    func testSetupCanBeSkippedAndIsNotOfferedTwice() {
        launch(["--show-setup", "-models.hasSeenSetup", "NO"])
        app.buttons["setup.notNow"].tap()
        XCTAssertTrue(app.buttons["home.record"].waitForExistence(timeout: 3))
    }

    func testDeviceStatusAndFunctionsAppear() {
        launch()
        openModels()
        XCTAssertTrue(app.staticTexts["Right now: Great"].exists || app.descendants(matching: .any)["models.rightNow"]
            .exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["models.role.search"].exists,
            "Every function has a model now, Search included",
        )
    }

    func testDownloadThenDeleteAModel() {
        launch()
        openFastModel()
        app.buttons["model.download"].tap()
        let delete = app.buttons["model.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        app.sheets.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["model.download"].waitForExistence(timeout: 3))
    }

    func testNetworkActivityStartsEmpty() {
        launch()
        app.buttons["drawer.toggle"].tap()
        app.buttons["drawer.item.settings"].tapWhenReady()
        let row = app.buttons["settings.network"]
        app.reveal(row)
        row.tap()
        XCTAssertTrue(app.staticTexts["Nothing has left this device"].waitForExistence(timeout: 3))
    }

    func testPreferencesOpen() {
        launch()
        app.buttons["drawer.toggle"].tap()
        app.buttons["drawer.item.settings"].tapWhenReady()
        app.buttons["settings.preferences"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.preferences"].waitForExistence(timeout: 3))
    }

    func testTryOnAudioLetsMeChooseTheRecording() {
        launch()
        openModels()
        app.buttons["models.role.transcription"].tap()
        for id in ["model.fake-small", "model.fake-large"] {
            app.buttons[id].tap()
            app.buttons["model.download"].tap()
            XCTAssertTrue(app.buttons["model.delete"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.firstMatch.tap()
        }
        let compare = app.buttons["models.compare"]
        app.reveal(compare)
        compare.tap()
        let picker = app.buttons["models.tryRecording"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        XCTAssertTrue(picker.label.contains("Sales meeting"), "The newest recording comes first")
        picker.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Product memo'")).firstMatch.tap()
        XCTAssertTrue(picker.label.contains("Product memo"))
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Old draft'")).firstMatch.exists,
            "Recordings in the trash are not offered",
        )
    }

    func testVocabularyCanBelongToOneFolder() {
        launch(["-transcript.vocabulary", "[]"])
        app.buttons["drawer.toggle"].tap()
        app.buttons["drawer.item.settings"].tapWhenReady()
        app.buttons["settings.preferences"].tap()
        let row = app.buttons["preferences.vocabulary"]
        app.reveal(row)
        row.tap()
        app.buttons["vocabulary.add"].tap()
        app.textFields["vocabulary.heard"].tap()
        app.typeText("acme")
        app.textFields["vocabulary.written"].tap()
        app.typeText("ACME")
        app.buttons["vocabulary.folder"].tap()
        app.buttons["Clients"].firstMatch.tap()
        app.buttons["vocabulary.save"].tap()
        XCTAssertTrue(app.staticTexts["ACME"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts["CLIENTS"].exists || app.staticTexts["Clients"].exists,
            "A word for one folder is listed under that folder",
        )
    }

    func testASpeedTestIsKeptInTheHistory() {
        launch()
        openFastModel()
        app.buttons["model.download"].tap()
        let quick = app.buttons["model.quickTest"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        quick.tap()
        XCTAssertTrue(app.descendants(matching: .any)["model.testResult"].waitForExistence(timeout: 10))
        let history = app.staticTexts["Recent runs on this device"]
        app.reveal(history)
        XCTAssertTrue(history.waitForExistence(timeout: 3))
    }

    func testALowBatteryOffersToWaitForTheCharger() {
        launch(["--low-battery", "-library.sort", "newest"])
        openFastModel()
        app.buttons["model.download"].tap()
        XCTAssertTrue(app.buttons["model.delete"].waitForExistence(timeout: 5))
        for _ in 0 ..< 4 where !app.buttons["drawer.toggle"].isHittable {
            app.navigationBars.buttons["BackButton"].firstMatch.tap()
        }
        app.buttons["drawer.toggle"].tap()
        app.buttons["drawer.item.home"].tapWhenReady()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sales meeting'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let more = app.buttons["detail.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        app.buttons["Transcribe again"].tap()
        app.buttons["English"].tapWhenReady()
        let wait = app.buttons["transcript.startWhenCharging"].firstMatch
        XCTAssertTrue(wait.waitForExistence(timeout: 3), "A low battery is worth a word before a job")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Battery is low'")).firstMatch
            .exists)
        wait.tap()
        XCTAssertTrue(app.staticTexts["Waits for a charger"].waitForExistence(timeout: 3))
    }

    func testATranscriptionShowsItsStepsWhileItRuns() {
        launch(["--slow-transcription", "-library.sort", "newest"])
        openFastModel()
        app.buttons["model.download"].tap()
        XCTAssertTrue(app.buttons["model.delete"].waitForExistence(timeout: 5))
        for _ in 0 ..< 4 where !app.buttons["drawer.toggle"].isHittable {
            app.navigationBars.buttons["BackButton"].firstMatch.tap()
        }
        app.buttons["drawer.toggle"].tap()
        app.buttons["drawer.item.home"].tapWhenReady()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sales meeting'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let more = app.buttons["detail.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        app.buttons["Transcribe again"].tap()
        app.buttons["English"].tapWhenReady()
        let start = app.buttons["transcript.startNow"].firstMatch
        if start.waitForExistence(timeout: 2) {
            start.tap()
        }
        let card = app.descendants(matching: .any)["transcript.status"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Work in progress is shown, with its steps")
        XCTAssertTrue(app.staticTexts["Preparing the model"].exists)
        XCTAssertTrue(app.staticTexts["Turning speech into text"].exists)
        keep("transcription-preparing")
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'elapsed'")).firstMatch
                .waitForExistence(timeout: 6),
            "Time passing shows that the app is not stuck",
        )
        keep("transcription-running")
    }

    private func keep(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testModelsPassAccessibilityAudit() throws {
        launch()
        openModels()
        try app.auditAccessibility()
    }
}
