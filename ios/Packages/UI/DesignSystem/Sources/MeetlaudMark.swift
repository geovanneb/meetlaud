import SwiftUI

/// The logo, tinted by the interface so that it works in Light and Dark.
public struct MeetlaudMark: View {
    private let height: CGFloat

    public init(height: CGFloat = 22) {
        self.height = height
    }

    public var body: some View {
        Image("MeetlaudMark", bundle: .module)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .foregroundStyle(Color.dsPrimaryText)
            .accessibilityHidden(true)
    }
}
