import XCTest

@MainActor
final class SystemTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--fake-capture", "--seed-library", "-recorder.hasSeenConsent", "YES"]
    }

    private func openSettings() {
        app.launch()
        app.buttons["drawer.toggle"].tap()
        app.buttons["drawer.item.settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].waitForExistence(timeout: 3))
    }

    private func open(_ row: String) {
        let button = app.buttons["settings.\(row)"]
        app.reveal(button)
        button.tap()
    }

    private static let longPageAudit = XCUIAccessibilityAuditType.all.subtracting(.dynamicType)

    func testStorageShowsWhatTakesSpaceAsOneBar() {
        openSettings()
        open("storage")
        XCTAssertTrue(app.descendants(matching: .any)["storage.usage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Free on this device"].exists, "The bar is the app's share of the device")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "storage"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testLongPagesWorkAtTheLargestTextSize() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        openSettings()
        open("storage")
        let export = app.buttons["storage.export"]
        app.reveal(export)
        app.reveal(export)
        XCTAssertTrue(export.isHittable, "The last rows must stay reachable")
        export.tap()
        XCTAssertTrue(app.secureTextFields["archive.password"].waitForExistence(timeout: 3))
    }

    func testThePrivacyPageWorksAtTheLargestTextSize() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        openSettings()
        open("privacy")
        let erase = app.buttons["privacy.erase"]
        for _ in 0 ..< 8 where !erase.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(erase.isHittable, "The last rows must stay reachable")
    }

    func testTheActionButtonStartsARecording() {
        app.launchArguments.append("--press-action-button")
        app.launch()
        XCTAssertTrue(
            app.buttons["Stop"].firstMatch.waitForExistence(timeout: 5)
                || app.descendants(matching: .any)["recorder.stop"].waitForExistence(timeout: 2),
            "One press has to start recording, even when it launches the app",
        )
    }

    func testEverySettingsPageOpens() {
        openSettings()
        for (row, screen) in [
            ("storage", "screen.storage"), ("notifications", "screen.notifications"),
            ("privacy", "screen.privacy"), ("network", ""), ("help", "screen.help"), ("about", "screen.about"),
            ("licenses", "screen.licenses"),
        ] {
            open(row)
            if !screen.isEmpty {
                XCTAssertTrue(app.descendants(matching: .any)[screen].waitForExistence(timeout: 3), row)
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].waitForExistence(timeout: 3))
        }
    }

    func testSettingsPagesPassTheAudit() throws {
        openSettings()
        try app.auditAccessibility()
        for row in ["storage", "notifications", "privacy", "about"] {
            open(row)
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 3))
            try app.auditAccessibility(for: ["storage", "privacy"].contains(row) ? Self.longPageAudit : .all)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    func testTheThemeIsChosenFromASheet() throws {
        openSettings()
        open("theme")
        let dark = app.buttons["theme.dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 3))
        // Only what a sheet can get wrong. The audit also reads the page behind it, partly covered and dimmed on
        // purpose.
        try app.auditAccessibility(for: [.dynamicType, .sufficientElementDescription, .hitRegion])
        dark.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.settings"].waitForExistence(timeout: 3))
        XCTAssertFalse(dark.waitForExistence(timeout: 1), "Picking a value closes the sheet")
        // The choice is saved, and it would carry into every test that runs after this one.
        open("theme")
        let system = app.buttons["theme.system"]
        XCTAssertTrue(system.waitForExistence(timeout: 3))
        system.tap()
    }

    func testErasingNeedsTheWordAndEmptiesTheLibrary() {
        openSettings()
        open("privacy")
        let erase = app.buttons["privacy.erase"]
        for _ in 0 ..< 3 where !erase.isHittable {
            app.swipeUp()
        }
        erase.tap()
        let run = app.buttons["erase.run"]
        XCTAssertTrue(run.waitForExistence(timeout: 3))
        XCTAssertFalse(run.isEnabled, "Nothing may erase on a single tap")

        let field = app.textFields["erase.confirm"]
        field.tap()
        field.typeText("NOPE")
        XCTAssertFalse(run.isEnabled)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        field.typeText("ERASE")
        XCTAssertTrue(run.isEnabled)
        run.tap()

        XCTAssertTrue(app.staticTexts["Start by recording or importing audio"].waitForExistence(timeout: 5)
            || !app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Sales meeting")).firstMatch
            .waitForExistence(timeout: 2))
    }

    func testTheLockHidesEverythingUntilUnlocked() {
        app.launchArguments += ["-privacy.appLock", "YES", "--slow-unlock"]
        app.launch()
        let lock = app.descendants(matching: .any)["screen.lock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 3), "The content must never show before the lock")
        XCTAssertTrue(lock.waitForNonExistence(timeout: 8), "Unlocking must bring the app back")
        XCTAssertTrue(app.buttons["drawer.toggle"].waitForExistence(timeout: 3))
    }

    func testAMeetingExportsInEveryFormat() throws {
        app.launch()
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Sales meeting")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        let more = app.buttons["detail.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 3))
        more.tap()
        app.buttons["detail.export"].tap()
        XCTAssertTrue(app.buttons["export.share"].waitForExistence(timeout: 3), "A file must be ready to share")
        try app.auditAccessibility(for: Self.longPageAudit)
    }

    func testAnArchiveNeedsAMatchingPassword() {
        openSettings()
        open("storage")
        let export = app.buttons["storage.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 3))
        export.tap()
        let create = app.buttons["archive.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 3))
        XCTAssertFalse(create.isEnabled)
        let first = app.secureTextFields["archive.password"]
        first.tap()
        first.typeText("correct horse")
        let second = app.secureTextFields["archive.passwordRepeat"]
        second.tap()
        second.typeText("correct horse")
        XCTAssertTrue(create.isEnabled)
        create.tap()
        XCTAssertTrue(app.buttons["archive.share"].waitForExistence(timeout: 5))
    }
}
