import XCTest

/// The features of 2026-11-08 on a physical iPhone, with real models and real audio: run history, try on my audio
/// with a chosen recording, vocabulary on a real transcript, and the note before a job.
/// The run leaves an imported clip and its transcript in the app, and removes the vocabulary word it adds.
@MainActor
final class RealDeviceFeatureTests: XCTestCase {
    private var app: XCUIApplication!
    private let written = "VOCABTEST"

    override func setUp() async throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Needs a physical device")
        #else
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = [
                "-recorder.hasSeenConsent", "YES", "-models.hasSeenSetup", "YES", "--import-speed-clip",
                "-library.sort", "newest",
            ]
            app.launch()
            let notice = app.alerts["Recording recovered"]
            if notice.waitForExistence(timeout: 3) {
                notice.buttons["OK"].tap()
            }
        #endif
    }

    func testNewModelFeaturesOnRealAudio() {
        speedTestLandsInHistory()
        let texts = tryOnTheImportedClip()
        let heard = texts.first?.split { !$0.isLetter }.map(String.init).first { $0.count >= 5 } ?? "speed"
        print("VOCABULARY: \(heard) -> \(written)")
        addVocabulary(heard)
        let transcript = transcribeNewestRecording()
        print("TRANSCRIPT: \(transcript)")
        XCTAssertTrue(transcript.contains(written), "The vocabulary must correct the real transcript")
        removeVocabulary()
    }

    private func open(_ item: String) {
        for _ in 0 ..< 3 where !app.buttons[item].exists {
            if app.navigationBars.buttons["BackButton"].exists {
                app.navigationBars.buttons["BackButton"].firstMatch.tap()
                usleep(400_000)
                continue
            }
            app.buttons["drawer.toggle"].tap()
            _ = app.buttons[item].waitForExistence(timeout: 2)
        }
        app.buttons[item].tap()
    }

    private func backToRoot() {
        for _ in 0 ..< 5 where app.navigationBars.buttons["BackButton"].exists {
            app.navigationBars.buttons["BackButton"].firstMatch.tap()
            usleep(400_000)
        }
    }

    private func speedTestLandsInHistory() {
        open("drawer.item.settings")
        app.buttons["settings.models"].tap()
        let role = app.buttons["models.role.transcription"]
        XCTAssertTrue(role.waitForExistence(timeout: 10))
        role.tap()
        app.buttons["model.whisper-small"].tap()
        let download = app.buttons["model.download"]
        if download.waitForExistence(timeout: 3) {
            download.tap()
        }
        let quick = app.buttons["model.quickTest"]
        XCTAssertTrue(quick.waitForExistence(timeout: 600))
        quick.tap()
        let running = app.staticTexts["Testing on this device"]
        _ = running.waitForExistence(timeout: 5)
        for _ in 0 ..< 180 where running.exists {
            sleep(1)
        }
        let history = app.staticTexts["Recent runs on this device"]
        app.reveal(history)
        XCTAssertTrue(history.waitForExistence(timeout: 10), "The test must appear in the history")
        print("HISTORY: shown")
        app.navigationBars.buttons["BackButton"].firstMatch.tap()
    }

    private func tryOnTheImportedClip() -> [String] {
        let compare = app.buttons["models.compare"]
        app.reveal(compare)
        XCTAssertTrue(compare.waitForExistence(timeout: 5), "Two transcription models must be installed")
        compare.tap()
        let picker = app.buttons["models.tryRecording"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        print("TRY PICKER: \(picker.label)")
        app.buttons["models.try"].tap()
        XCTAssertTrue(app.staticTexts["models.trialText"].firstMatch.waitForExistence(timeout: 600))
        sleep(2)
        let texts = app.staticTexts.matching(identifier: "models.trialText").allElementsBoundByIndex.map(\.label)
        for text in texts {
            print("TRIAL: \(text)")
        }
        XCTAssertEqual(texts.count, 2, "Both models must finish")
        return texts
    }

    private func openVocabulary() {
        backToRoot()
        open("drawer.item.settings")
        app.buttons["settings.preferences"].tap()
        let vocabulary = app.buttons["preferences.vocabulary"]
        app.reveal(vocabulary)
        vocabulary.tap()
    }

    private func addVocabulary(_ heard: String) {
        openVocabulary()
        app.buttons["vocabulary.add"].tap()
        app.textFields["vocabulary.heard"].tap()
        app.typeText(heard)
        app.textFields["vocabulary.written"].tap()
        app.typeText(written)
        app.buttons["vocabulary.save"].tap()
        XCTAssertTrue(app.staticTexts[written].waitForExistence(timeout: 3))
    }

    /// A note may come first, depending on the battery and heat right now.
    private func transcribeNewestRecording() -> String {
        backToRoot()
        open("drawer.item.home")
        let row = app.buttons["recording.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        print("ROW: \(row.label)")
        row.tap()
        let start = app.buttons["transcript.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        app.buttons["English"].tap()
        let now = app.buttons["transcript.startNow"].firstMatch
        if now.waitForExistence(timeout: 3) {
            let note = app.staticTexts.allElementsBoundByIndex.map(\.label)
                .filter { $0.contains("min") || $0.contains("Right now") }
            print("NOTE: \(note.joined(separator: " | "))")
            now.tap()
        } else {
            print("NOTE: none, the job was short and the device was fine")
        }
        XCTAssertTrue(app.buttons["transcript.segment"].firstMatch.waitForExistence(timeout: 180))
        sleep(10)
        return app.buttons.matching(identifier: "transcript.segment").allElementsBoundByIndex.map(\.label)
            .joined(separator: " | ")
    }

    private func removeVocabulary() {
        openVocabulary()
        let word = app.staticTexts[written]
        XCTAssertTrue(word.waitForExistence(timeout: 3))
        word.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts[written].waitForExistence(timeout: 2))
    }
}
