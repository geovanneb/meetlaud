import DesignSystem
import Localization
import SwiftUI

public struct HelpView: View {
    public init() {}

    private var topics: [(title: String, body: String)] {
        [
            (L10n.System.helpRecordTitle, L10n.System.helpRecordBody),
            (L10n.System.helpConsentTitle, L10n.System.helpConsentBody),
            (L10n.System.helpModelsTitle, L10n.System.helpModelsBody),
            (L10n.System.helpAskTitle, L10n.System.helpAskBody),
            (L10n.System.helpShortcutsTitle, L10n.System.helpShortcutsBody),
            (L10n.System.helpMoveTitle, L10n.System.helpMoveBody),
        ]
    }

    public var body: some View {
        List {
            ForEach(topics, id: \.title) { topic in
                Section(title: topic.title) {
                    Text(topic.body)
                }
                .listRowBackground(Color.clear)
            }
        }
        .screenList()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.Nav.help)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.help")
    }
}
