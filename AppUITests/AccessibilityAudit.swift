import XCTest

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
        try performAccessibilityAudit(for: types) { issue in
            // Toolbars keep a fixed size and use the Large Content Viewer, as Apple recommends.
            if issue.auditType == .dynamicType, let label = issue.element?.label,
               label == "Record" || self.navigationBars.buttons[label].exists
            {
                return true
            }
            // Text scrolled behind a bar exists but cannot be seen, so its contrast means nothing.
            // So is text cut off by the bottom of the screen, a line that only shows its top few points.
            if issue.auditType == .contrast, let element = issue.element,
               !element.isHittable || element.frame.intersects(barFrame) || element.frame.maxY > self.frame.maxY
            {
                return true
            }
            let element = issue.element.map { "\($0.elementType.rawValue) \'\($0.label)\'" } ?? "unknown element"
            print("AUDIT: \(issue.compactDescription): \(element)")
            return false
        }
    }
}
