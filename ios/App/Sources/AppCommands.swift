import AppRouting
import FeatureRecording
import Localization
import SwiftUI

/// Keyboard shortcuts on iPad, also listed in the system's menu. Space lives on the player itself.
struct AppCommands: Commands {
    let router: AppRouter
    let recorder: RecordingController

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L10n.Home.startRecording) { recorder.record() }
                .keyboardShortcut("n")
            Button(L10n.Library.search) { router.open(.search) }
                .keyboardShortcut("f")
            Button(L10n.Nav.ask) { router.open(.ask(recording: nil)) }
                .keyboardShortcut("k")
        }
    }
}
