import SwiftUI

/// Centered empty state. Replaces `ContentUnavailableView`, whose title fails the Dynamic Type audit.
public struct EmptyState: View {
    private let title: String
    private let message: String
    private let symbol: String

    public init(title: String, message: String, symbol: String) {
        self.title = title
        self.message = message
        self.symbol = symbol
    }

    public var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.small) {
                    Image(systemName: symbol)
                        .font(.dsHero)
                        .foregroundStyle(Color.dsSecondaryText)
                        .padding(.bottom, Spacing.small)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.dsSectionTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(.dsMeta)
                        .foregroundStyle(Color.dsSecondaryText)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Spacing.large)
                // A minimum, so that large text grows and scrolls instead of being clipped.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

#Preview {
    EmptyState(title: "No recordings yet", message: "Start by recording.", symbol: "doc.text.magnifyingglass")
}
