import DesignSystem
import SwiftUI

/// The way into a chat from any screen. The chat belongs to another feature, so each screen decides where this goes.
public struct AskEntryBar: View {
    private let title: String
    private let action: () -> Void

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        PromptBar(placeholder: title, action: action)
    }
}
