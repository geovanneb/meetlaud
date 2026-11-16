import SwiftUI

public struct Choice<Value: Hashable>: Identifiable {
    public let value: Value
    public let title: String
    public let symbol: String?
    public let identifier: String?

    public var id: Value {
        value
    }

    public init(_ value: Value, title: String, symbol: String? = nil, identifier: String? = nil) {
        self.value = value
        self.title = title
        self.symbol = symbol
        self.identifier = identifier
    }
}

/// A large title and a round close button, at the top of a sheet that is only as tall as its content.
public struct SheetHeader: View {
    private let title: String
    private let closeLabel: String
    @Environment(\.dismiss) private var dismiss

    public init(title: String, closeLabel: String) {
        self.title = title
        self.closeLabel = closeLabel
    }

    public var body: some View {
        HStack {
            Text(title)
                .font(.dsPageTitle)
                .foregroundStyle(Color.dsPrimaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.small)
            Button {
                dismiss()
            } label: {
                Label(closeLabel, systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .tappableTarget()
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .foregroundStyle(Color.dsPrimaryText)
            .accessibilityIdentifier("choice.close")
        }
    }
}

/// A short list of options in a sheet from the bottom, only as tall as its content.
/// For a setting with a few values: picking one is a single tap, and the screen behind stays in view.
public struct ChoiceSheet<Value: Hashable>: View {
    private let title: String
    private let closeLabel: String
    private let choices: [Choice<Value>]
    @Binding private var selection: Value
    @State private var height: CGFloat = 280
    @Environment(\.dismiss) private var dismiss

    public init(title: String, closeLabel: String, choices: [Choice<Value>], selection: Binding<Value>) {
        self.title = title
        self.closeLabel = closeLabel
        self.choices = choices
        _selection = selection
    }

    public var body: some View {
        // Scrolls only when large text makes the content taller than the screen.
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.small) {
                SheetHeader(title: title, closeLabel: closeLabel)
                ForEach(choices, content: row)
            }
            .padding(Spacing.large)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(height)])
        .presentationBackground(Color.dsSurface)
    }

    private func row(_ choice: Choice<Value>) -> some View {
        let isSelected = choice.value == selection
        return Button {
            selection = choice.value
            dismiss()
        } label: {
            HStack(spacing: Spacing.compact) {
                if let symbol = choice.symbol {
                    Image(systemName: symbol)
                        .frame(width: Spacing.large)
                        .accessibilityHidden(true)
                }
                Text(choice.title)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.small)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.dsAction)
                        .accessibilityHidden(true)
                }
            }
            .font(.dsRowTitle)
            .foregroundStyle(Color.dsPrimaryText)
            .tappableTarget()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(choice.identifier ?? "")
    }
}

/// A row that opens something: an icon, a title, the current value, and a chevron.
public struct SettingsRowLabel: View {
    private let title: String
    private let symbol: String?
    private let value: String?

    public init(_ title: String, symbol: String? = nil, value: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.value = value
    }

    public var body: some View {
        HStack(spacing: Spacing.medium) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(Color.dsSecondaryText)
                    .frame(width: Spacing.large)
                    .accessibilityHidden(true)
            }
            Text(title)
                .foregroundStyle(Color.dsPrimaryText)
            Spacer(minLength: Spacing.small)
            if let value {
                Text(value)
                    .foregroundStyle(Color.dsSecondaryText)
            }
            Image(systemName: "chevron.right")
                .font(.dsNote)
                .foregroundStyle(Color.dsSecondaryText)
                .accessibilityHidden(true)
        }
        .tappableTarget()
    }
}
