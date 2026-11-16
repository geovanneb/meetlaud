import SwiftUI

/// Native buttons, dressed the same way everywhere.
///
/// Size comes from the control size. Do not add a frame to a label to make a button bigger: the style pads around it,
/// and the button grows out of proportion. Use `.frame(maxWidth: .infinity)` only for the one action at the foot of a
/// sheet.
public extension View {
    /// The main action of a screen. A screen has one at most.
    func primaryAction() -> some View {
        buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Color.dsAction)
            .foregroundStyle(Color.dsOnAction)
    }

    /// An action that stands on its own without competing with the primary one.
    func secondaryAction(_ size: ControlSize = .large) -> some View {
        buttonStyle(SecondaryActionStyle())
            .controlSize(size)
    }
}

/// A solid outlined capsule. Custom because the system's options fail the contrast audit here: glass over a light
/// background, and a bordered button tinted dark enough to read. It keeps Dynamic Type and a 44-point target, and it
/// does not move, so Reduce Motion has nothing to change.
private struct SecondaryActionStyle: ButtonStyle {
    @Environment(\.controlSize) private var size
    @Environment(\.isEnabled) private var isEnabled

    private var padding: EdgeInsets {
        switch size {
        case .large, .extraLarge:
            EdgeInsets(top: Spacing.compact, leading: Spacing.large, bottom: Spacing.compact, trailing: Spacing.large)
        case .regular:
            EdgeInsets(top: Spacing.small, leading: Spacing.medium, bottom: Spacing.small, trailing: Spacing.medium)
        default:
            EdgeInsets(top: Spacing.xSmall, leading: Spacing.compact, bottom: Spacing.xSmall, trailing: Spacing.compact)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size == .large ? .dsRowTitle : .dsMeta)
            .foregroundStyle(isEnabled ? Color.dsPrimaryText : Color.dsSecondaryText)
            .padding(padding)
            .background(configuration.isPressed ? Color.dsSelection : Color.dsSurface, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.dsSelection))
            .frame(minHeight: 44)
            .contentShape(.rect)
    }
}

/// A title with a line of detail under it. The shape of almost every row in the app.
public struct RowLabel: View {
    private let title: String
    private let detail: String
    private let titleLines: Int?

    public init(_ title: String, detail: String, titleLines: Int? = nil) {
        self.title = title
        self.detail = detail
        self.titleLines = titleLines
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(title)
                .font(.dsRowTitle)
                .foregroundStyle(Color.dsPrimaryText)
                .lineLimit(titleLines)
            Text(detail)
                .font(.dsMeta)
                .foregroundStyle(Color.dsSecondaryText)
        }
    }
}
