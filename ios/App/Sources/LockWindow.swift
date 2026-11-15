import FeatureShared
import SwiftUI
import UIKit

/// The cover sits in its own window, because sheets and the recording screen float above any view in the main one.
@MainActor
final class LockWindow {
    private var windows: [UIWindow] = []
    private let controller: AppLockController
    private var isTracking = false

    init(controller: AppLockController) {
        self.controller = controller
    }

    /// Starts following the lock. Waits for this call because windows need a scene, and scenes arrive after launch.
    func start() {
        guard !isTracking else { return }
        isTracking = true
        track()
    }

    /// At launch the cover can be needed before any scene exists, and nothing would change to try again.
    func refresh() {
        update(isCovered: controller.state.isCovered)
    }

    /// Observation fires once per registration, so this registers again after each change.
    private func track() {
        withObservationTracking {
            update(isCovered: controller.state.isCovered)
        } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
    }

    private func update(isCovered: Bool) {
        guard isCovered else {
            windows.forEach { $0.isHidden = true }
            windows = []
            return
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes where !windows.contains(where: { $0.windowScene == scene }) {
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.rootViewController = UIHostingController(rootView: LockScreen(controller: controller))
            window.isHidden = false
            windows.append(window)
        }
    }
}
