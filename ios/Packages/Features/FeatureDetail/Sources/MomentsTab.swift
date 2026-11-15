import DesignSystem
import Domain
import Localization
import SwiftUI

/// The flags, notes, and photos of a recording. Each one plays its moment.
struct MomentsTab: View {
    let model: DetailModel

    var body: some View {
        if model.markers.isEmpty {
            EmptyState(title: L10n.Detail.moments, message: L10n.Detail.noMoments, symbol: "flag")
                .fillsTab()
        } else {
            VStack(alignment: .leading, spacing: Spacing.small) {
                ForEach(model.markers, content: row)
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
        }
    }

    private func row(_ marker: Marker) -> some View {
        Button {
            model.play(from: marker.time)
        } label: {
            HStack(spacing: Spacing.small) {
                Text(marker.time.clock)
                    .font(.dsTimestamp)
                    .foregroundStyle(Color.dsSecondaryText)
                if let image = model.image(for: marker) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(.rect(cornerRadius: Radius.small))
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: marker.kind == .note ? "square.and.pencil" : "flag.fill")
                        .foregroundStyle(Color.dsAction)
                        .accessibilityHidden(true)
                }
                Text(marker.text ?? L10n.Detail.moment)
                    .font(.dsRowTitle)
                    .foregroundStyle(Color.dsPrimaryText)
                Spacer(minLength: 0)
            }
            .tappableTarget()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Gives a tab's empty or prompt state room to sit centered, inside a scroll view that has no height of its own.
    func fillsTab() -> some View {
        containerRelativeFrame(.vertical, alignment: .center) { height, _ in height * 0.6 }
    }
}
