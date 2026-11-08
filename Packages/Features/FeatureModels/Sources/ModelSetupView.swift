import DesignSystem
import Domain
import Localization
import SwiftUI

/// The one-tap setup. It names functions, not models, because that is what people care about.
public struct ModelSetupView: View {
    private let controller: ModelsController
    private let onCustomize: () -> Void
    @Environment(\.dismiss) private var dismiss

    public init(controller: ModelsController, onCustomize: @escaping () -> Void) {
        self.controller = controller
        self.onCustomize = onCustomize
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            MeetlaudMark(height: 36)
            Text(L10n.Models.setupTitle)
                .font(.dsPageTitle)
                .accessibilityAddTraits(.isHeader)
            if let snapshot = controller.snapshot {
                Text(L10n.Models.setupFor(snapshot.device.name))
                    .foregroundStyle(Color.dsSecondaryText)
                VStack(alignment: .leading, spacing: Spacing.small) {
                    ForEach(ModelRole.allCases.filter { !(snapshot.fits[$0] ?? []).isEmpty }, id: \.self) { role in
                        Label(role.title, systemImage: "checkmark")
                    }
                }
                Text(L10n.Models.setupSize(total(snapshot).fileSize, snapshot.condition.freeBytes.fileSize))
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
                Text(L10n.Models.setupNote)
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
            }
            Spacer(minLength: 0)
            Button {
                controller.installRecommended()
                dismiss()
            } label: {
                Text(L10n.Models.downloadAll)
                    .frame(maxWidth: .infinity)
            }
            .primaryAction()
            .accessibilityIdentifier("setup.download")
            HStack {
                Button(L10n.Models.customize) {
                    dismiss()
                    onCustomize()
                }
                .accessibilityIdentifier("setup.customize")
                Spacer()
                Button(L10n.Models.notNow) { dismiss() }
                    .accessibilityIdentifier("setup.notNow")
            }
            .frame(minHeight: 44)
        }
        .padding(Spacing.large)
        .presentationDetents([.medium, .large])
    }

    private func total(_ snapshot: ModelsSnapshot) -> Int64 {
        snapshot.missingFromSetup.reduce(0) { $0 + $1.totalBytes }
    }
}
