import AppRouting
import Domain
import FeatureShared
import Localization
import SwiftUI

struct AskBar: View {
    let id: RecordingID
    @AppStorage(AskPreferences.promptBarKey) private var promptBar = AskPreferences.PromptBar.focus.rawValue
    @Environment(AppRouter.self) private var router

    var body: some View {
        AskEntryBar(title: L10n.Ask.aboutMeeting) {
            if promptBar == AskPreferences.PromptBar.newChat.rawValue {
                router.open(.ask(recording: nil))
            } else {
                router.push(.ask(recording: id))
            }
        }
        .accessibilityIdentifier("detail.ask")
    }
}
