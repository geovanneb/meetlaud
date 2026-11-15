import XCTest

/// Runs only on a physical iPhone: real microphone, real database, real file system.
/// Each run leaves test recordings in the app.
@MainActor
final class RealDeviceCaptureTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Needs a physical device")
        #else
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = ["-recorder.hasSeenConsent", "YES"]
            addUIInterruptionMonitor(withDescription: "Permissions") { alert in
                for label in ["Allow", "OK", "\u{8A31}\u{53EF}"] where alert.buttons[label].exists {
                    alert.buttons[label].tap()
                    return true
                }
                return false
            }
            app.launch()
            dismissRecoveryNotice()
        #endif
    }

    /// A previous run may have left a killed recording behind.
    private func dismissRecoveryNotice() {
        let notice = app.alerts["Recording recovered"]
        if notice.waitForExistence(timeout: 3) {
            notice.buttons["OK"].tap()
        }
    }

    /// The combined element's label holds the time and the status.
    private var recordedSeconds: Int {
        let label = app.descendants(matching: .any)["recorder.time"].label
        let clock = label.split(separator: ",").first.map(String.init) ?? label
        return seconds(in: clock.trimmingCharacters(in: .whitespaces))
    }

    private func startRecording() {
        app.buttons["home.record"].tap()
        app.tap() // Lets the interruption monitor answer the microphone prompt.
        XCTAssertTrue(app.buttons["recorder.stop"].waitForExistence(timeout: 10))
    }

    private func seconds(in label: String) -> Int {
        let parts = label.split(separator: ":").compactMap { Int($0) }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    func testRecordRealAudioAndPlayIt() {
        startRecording()
        sleep(12)
        XCTAssertGreaterThanOrEqual(recordedSeconds, 10, "The clock follows real audio frames")

        app.buttons["recorder.flag"].tap()
        app.buttons["recorder.stop"].tap()
        XCTAssertTrue(app.buttons["player.toggle"].waitForExistence(timeout: 15), "The final file must open")
        app.buttons["player.toggle"].tap()
        sleep(2)
        XCTAssertEqual(app.buttons["player.toggle"].label, "Pause")
    }

    /// A tap during an alert's closing animation is swallowed, so this waits for the menu to really open.
    private func open(_ item: String) {
        for _ in 0 ..< 3 where !app.buttons[item].exists {
            app.buttons["drawer.toggle"].tap()
            _ = app.buttons[item].waitForExistence(timeout: 2)
        }
        app.buttons[item].tap()
    }

    /// The whole promise, on real hardware: a real download, a real model, real audio, real text.
    func testDownloadModelTestSpeedAndTranscribeRealSpeech() {
        app.terminate()
        app.launchArguments = [
            "-recorder.hasSeenConsent", "YES", "-models.hasSeenSetup", "YES", "--import-speed-clip",
            // The clip this run imports must be the first row, whatever order the phone has saved.
            "-library.sort", "newest",
        ]
        app.launch()
        dismissRecoveryNotice()

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
        let test = app.buttons["model.quickTest"]
        XCTAssertTrue(test.waitForExistence(timeout: 600), "Download, verify, and prepare must finish")

        test.tap()
        // The result also updates the speed at the top, which stays on screen.
        let measured = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "measured here")).firstMatch
        XCTAssertTrue(measured.waitForExistence(timeout: 120), "The speed test must finish")
        // An earlier run may have left a measurement, so also wait for this test to end.
        let running = app.staticTexts["Testing on this device"]
        for _ in 0 ..< 120 where running.exists {
            sleep(1)
        }
        print("SPEED: \(measured.label)")

        for _ in 0 ..< 4 where app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
            usleep(400_000)
        }
        open("drawer.item.home")
        let row = app.buttons["recording.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let start = app.buttons["transcript.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        app.buttons["English"].tap()

        let segment = app.buttons["transcript.segment"].firstMatch
        XCTAssertTrue(segment.waitForExistence(timeout: 120), "Real speech must become real text")
        sleep(10)
        let text = app.buttons.matching(identifier: "transcript.segment").allElementsBoundByIndex.map(\.label)
        print("TRANSCRIPT: \(text.joined(separator: " | "))")
        XCTAssertFalse(text.isEmpty)

        segment.tap()
        sleep(1)
        XCTAssertEqual(app.buttons["player.toggle"].label, "Pause", "Tapping a phrase must play it")
    }

    /// The speaker model on the real Neural Engine, after a real transcription. The clip has one voice.
    func testDownloadSpeakerModelAndSeparateSpeakers() {
        app.terminate()
        app.launchArguments = [
            "-recorder.hasSeenConsent", "YES", "-models.hasSeenSetup", "YES", "--import-speed-clip",
            // The clip this run imports must be the first row, whatever order the phone has saved.
            "-library.sort", "newest",
        ]
        app.launch()
        dismissRecoveryNotice()

        open("drawer.item.settings")
        app.buttons["settings.models"].tap()
        let role = app.buttons["models.role.speakerSeparation"]
        XCTAssertTrue(role.waitForExistence(timeout: 10))
        role.tap()
        app.buttons["model.pyannote-community-1"].tap()
        let download = app.buttons["model.download"]
        if download.waitForExistence(timeout: 3) {
            download.tap()
        }
        XCTAssertTrue(app.buttons["model.delete"].waitForExistence(timeout: 300), "Install must finish")

        for _ in 0 ..< 4 where app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
            usleep(400_000)
        }
        open("drawer.item.home")
        let row = app.buttons["recording.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let start = app.buttons["transcript.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        app.buttons["English"].tap()

        let chip = app.buttons["speaker.chip"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 180), "Speakers must appear after the text")
        print("SPEAKER: \(chip.label)")
    }

    /// SP-1. Downloads the language model through the app, then lets the probe run on real hardware.
    /// Results land in the app's Documents folder, which the Mac copies afterwards.
    func testLanguageModelProbe() {
        app.terminate()
        app.launchArguments = ["-recorder.hasSeenConsent", "YES", "-models.hasSeenSetup", "YES"]
        app.launch()
        dismissRecoveryNotice()

        open("drawer.item.settings")
        app.buttons["settings.models"].tap()
        let role = app.buttons["models.role.chat"]
        XCTAssertTrue(role.waitForExistence(timeout: 10))
        role.tap()
        app.buttons["model.qwen35-2b"].tap()
        let download = app.buttons["model.download"]
        if download.waitForExistence(timeout: 3) {
            download.tap()
        }
        XCTAssertTrue(app.buttons["model.delete"].waitForExistence(timeout: 900), "Install must finish")

        app.terminate()
        app.launchArguments = [
            "-recorder.hasSeenConsent", "YES", "-models.hasSeenSetup", "YES", "--llm-probe",
        ]
        app.launch()
        // Keeps the app in the foreground. The Mac reads the results when this ends.
        for second in 0 ..< 420 {
            sleep(1)
            if second % 30 == 0 {
                print("PROBE \(second)s state=\(app.state.rawValue)")
            }
            XCTAssertEqual(app.state, .runningForeground, "The app must survive the probe")
        }
    }

    /// F5. The real summary pipeline on invented meetings of 1 and 3 hours. Long by nature: it keeps the app in the
    /// foreground, and the Mac stops it when `summary-probe.status` in Documents says "done".
    func testSummaryProbe() {
        app.terminate()
        app.launchArguments = [
            "-recorder.hasSeenConsent", "YES", "-models.hasSeenSetup", "YES", "--summary-probe",
        ]
        app.launch()
        for second in 0 ..< 3000 {
            sleep(1)
            if second % 60 == 0 {
                print("PROBE \(second)s state=\(app.state.rawValue)")
            }
            XCTAssertEqual(app.state, .runningForeground, "The app must survive the probe")
        }
    }

    /// A forum report claims suspension after 30 seconds. This measures it past that point.
    func testRecordingContinuesInTheBackground() {
        startRecording()
        sleep(2)
        let before = recordedSeconds

        XCUIDevice.shared.press(.home)
        sleep(45)
        app.activate()

        XCTAssertTrue(app.buttons["recorder.stop"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(recordedSeconds - before, 44, "Audio must keep flowing in the background")
        app.buttons["recorder.stop"].tap()
        XCTAssertTrue(app.buttons["player.toggle"].waitForExistence(timeout: 15))
    }

    /// Kills the process mid-recording, which is what a crash does, and expects the audio back.
    func testKilledMidRecordingIsRecoveredOnNextLaunch() {
        // The phone's saved sort order must not hide the newest row below the fold.
        app.launchArguments += ["-library.sort", "newest"]
        startRecording()
        sleep(15)
        XCTAssertGreaterThanOrEqual(recordedSeconds, 12)

        app.terminate()
        app.launch()

        let notice = app.alerts["Recording recovered"]
        XCTAssertTrue(notice.waitForExistence(timeout: 15), "Recovery must tell the user")
        notice.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["recording.row"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["recording.row"].firstMatch.label.contains("Recovered"))
    }
}
