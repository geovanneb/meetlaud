import SwiftUI

/// A list section title with real contrast. The system's default fails the accessibility audit on these backgrounds.
public struct SectionHeader: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.dsMeta)
            .foregroundStyle(Color.dsSecondaryText)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

@MainActor
public extension Section where Parent == SectionHeader, Footer == EmptyView, Content: View {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { SectionHeader(title) })
    }
}
