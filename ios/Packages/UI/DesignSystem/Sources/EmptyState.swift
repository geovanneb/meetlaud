import SwiftUI

/// Centered empty state. Replaces `ContentUnavailableView`, whose title fails the Dynamic Type audit.
public struct EmptyState: View {
    private let title: String
    private let message: String
    private let symbol: String

    public init(title: String, message: String, symbol: String, inline: Bool = false) {
        self.title = title
        self.message = message
        self.symbol = symbol
        self.inline = inline
    }

    /// Inline states take their natural height inside the parent list, including at accessibility text sizes.
    private let inline: Bool

    public var body: some View {
        if inline {
            content
        } else {
            GeometryReader { proxy in
                ScrollView {
                    content.frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private var content: some View {
        VStack(spacing: Spacing.small) {
            Image(systemName: symbol)
                .font(.dsHero)
                .foregroundStyle(Color.dsSecondaryText)
                .padding(.bottom, Spacing.small)
                .accessibilityHidden(true)
            Text(title)
                .font(.dsSectionTitle)
                .foregroundStyle(Color.dsPrimaryText)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.dsMeta)
                .foregroundStyle(Color.dsSecondaryText)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(Spacing.large)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    EmptyState(title: "No recordings yet", message: "Start by recording.", symbol: "doc.text.magnifyingglass")
}
