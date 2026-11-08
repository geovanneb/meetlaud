import SwiftUI

/// The size of everything that looks like the place to ask. A prompt looks the same before and after it opens.
public enum PromptMetrics {
    public static let minimumHeight: CGFloat = 56
    /// Half the height: a capsule on one line, and a rounded card when the text grows.
    public static let cornerRadius: CGFloat = minimumHeight / 2
    public static let textInset = Spacing.large
}

public extension View {
    /// Where a prompt sits: floating over the content, with the same margins on every screen.
    func promptPlacement() -> some View {
        padding(.horizontal, Spacing.medium)
            .padding(.bottom, Spacing.small)
    }
}

/// The bar at the bottom of main screens, where a thumb already rests.
public struct PromptBar: View {
    private let placeholder: String
    private let action: () -> Void

    public init(placeholder: String, action: @escaping () -> Void) {
        self.placeholder = placeholder
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack {
                Text(placeholder)
                    .foregroundStyle(Color.dsSecondaryText)
                Spacer(minLength: Spacing.small)
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.dsSecondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, PromptMetrics.textInset)
            .padding(.vertical, Spacing.small)
            .frame(minHeight: PromptMetrics.minimumHeight)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .promptPlacement()
        .accessibilityLabel(placeholder)
    }
}

#Preview {
    PromptBar(placeholder: "Ask about your recordings") {}
        .frame(maxHeight: .infinity, alignment: .bottom)
        .screenBackground()
}
