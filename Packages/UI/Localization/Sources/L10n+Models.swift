import Foundation

/// The one-tap setup's progress on the AI models screen.
public extension L10n.Models {
    static var setupFinishing: String { L10n.text("models.setup_finishing") }
    static var setupBackground: String { L10n.text("models.setup_background") }
    static var resumeAll: String { L10n.text("models.resume_all") }

    static func setupDownloading(_ received: String, _ total: String) -> String {
        String(format: L10n.text("models.setup_downloading"), received, total)
    }

    static func setupPaused(_ received: String, _ total: String) -> String {
        String(format: L10n.text("models.setup_paused"), received, total)
    }
}
