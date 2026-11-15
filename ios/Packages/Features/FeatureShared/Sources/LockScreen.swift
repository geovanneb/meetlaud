import DesignSystem
import Domain
import Localization
import SwiftUI

/// Hides everything: from the app switcher, and from anyone holding an unlocked phone.
public struct LockScreen: View {
    private let controller: AppLockController

    public init(controller: AppLockController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: Spacing.medium) {
            Image(systemName: "lock.fill")
                .font(.dsHero)
                .foregroundStyle(Color.dsSecondaryText)
                .accessibilityHidden(true)
            if controller.state.isLocked {
                Text(L10n.System.lockedTitle)
                    .font(.dsSectionTitle)
                Button(L10n.System.unlock, action: controller.unlock)
                    .primaryAction()
                    .accessibilityIdentifier("lock.unlock")
            }
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBackground.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.lock")
    }
}
