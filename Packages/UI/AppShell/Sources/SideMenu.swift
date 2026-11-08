import AppRouting
import DesignSystem
import Localization
import SwiftUI

struct SideMenu: View {
    let selected: Destination
    let onSelect: (Destination) -> Void
    let onSearch: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                HStack {
                    MeetlaudMark()
                        .padding(.leading, Spacing.medium)
                    Spacer()
                    Button(action: onSearch) {
                        Label(L10n.Library.search, systemImage: "magnifyingglass")
                            .labelStyle(.iconOnly)
                            .font(.dsIcon)
                            .tappableTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("drawer.search")
                }
                ForEach(Destination.primary, id: \.self, content: row)
                Divider().padding(.vertical, Spacing.small)
                ForEach(Destination.secondary, id: \.self, content: row)
            }
            .padding(.horizontal, Spacing.small)
            .padding(.top, Spacing.medium)
        }
    }

    private func row(_ destination: Destination) -> some View {
        Button {
            onSelect(destination)
        } label: {
            HStack(spacing: Spacing.medium) {
                Image(systemName: destination.symbol)
                    .frame(width: Spacing.large)
                    .accessibilityHidden(true)
                Text(destination.title)
            }
            .font(.dsMenuRow)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.medium)
            .background(
                destination == selected ? Color.dsSelection : .clear,
                in: .rect(cornerRadius: Radius.small),
            )
            .contentShape(.rect)
            .motion(Motion.quick, value: destination == selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(destination == selected ? .isSelected : [])
        .accessibilityIdentifier("drawer.item.\(destination.rawValue)")
    }
}

private extension Destination {
    var title: String {
        switch self {
        case .home: L10n.Nav.home
        case .library: L10n.Nav.library
        case .ask: L10n.Nav.ask
        case .tools: L10n.Nav.tools
        case .settings: L10n.Nav.settings
        case .help: L10n.Nav.help
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .library: "folder"
        case .ask: "sparkles"
        case .tools: "wrench.and.screwdriver"
        case .settings: "gearshape"
        case .help: "questionmark.circle"
        }
    }
}
