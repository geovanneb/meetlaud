import XCTest

extension XCUIElement {
    /// Taps once the element is there. A drawer or menu that just opened can still be moving in on a slow CI
    /// machine, and a plain `tap()` then fails with "No matches found".
    func tapWhenReady(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForExistence(timeout: timeout), "\(self) did not appear", file: file, line: line)
        tap()
    }
}

extension XCUIApplication {
    /// Scrolls until the element sits fully on screen. `isHittable` alone is not enough: a row showing a few points
    /// at the bottom edge counts as hittable, and a tap on its center lands off the screen.
    func reveal(_ element: XCUIElement) {
        for _ in 0 ..< 6 where !(element.isHittable && element.frame.maxY < frame.maxY - 8) {
            swipeUp()
        }
    }

    /// Runs Apple's audit, and names each element it rejects.
    /// `.all` by default. Long pages skip Dynamic Type here: the audit enlarges the text, which pushes rows off the
    /// screen, and it reports that as a failure. `SystemTests` opens those pages at the largest size instead.
    func auditAccessibility(for types: XCUIAccessibilityAuditType = .all) throws {
        // Lists scroll under the floating "Ask about…" bar, and iOS fades the strip just above it on purpose. The
        // audit still sees the text there.
        let bar = descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Ask about'")).firstMatch
        let barFrame = bar.exists ? bar.frame.insetBy(dx: 0, dy: -40) : .null
        // The search field floats over the bottom of a screen the same way, and blurs what scrolls under it.
        let search = searchFields.firstMatch
        let searchFrame = search.exists ? search.frame.insetBy(dx: 0, dy: -24) : .null
        let isExpected = { (issue: XCUIAccessibilityAuditIssue) -> Bool in
            // Toolbars keep a fixed size and use the Large Content Viewer, as Apple recommends.
            // A query by label longer than 128 characters throws, and no toolbar button is that long.
            if issue.auditType == .dynamicType, let label = issue.element?.label,
               label == "Record" || label.count <= 128 && self.navigationBars.buttons[label].exists
            {
                return true
            }
            // Text scrolled behind a bar exists but cannot be seen, so its contrast means nothing.
            // So is text cut off by the bottom of the screen, a line that only shows its top few points.
            if issue.auditType == .contrast, let element = issue.element,
               !element.isHittable || element.frame.intersects(barFrame) || element.frame.intersects(searchFrame)
               || element.frame.maxY > self.frame.maxY
            {
                return true
            }
            return false
        }
        // The first pass only looks. A view still moving into place can be reported as clipped once (a summary that
        // just appeared, on a slow CI machine). A real problem is still there a second later, and fails below.
        var foundIssue = false
        try performAccessibilityAudit(for: types) { issue in
            if !isExpected(issue) {
                foundIssue = true
            }
            return true
        }
        guard foundIssue else { return }
        Thread.sleep(forTimeInterval: 1)
        try performAccessibilityAudit(for: types) { issue in
            if isExpected(issue) {
                return true
            }
            let element = issue.element.map { "\($0.elementType.rawValue) \'\($0.label)\'" } ?? "unknown element"
            print("AUDIT: \(issue.compactDescription): \(element)")
            return false
        }
    }
}
