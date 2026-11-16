import Domain
import Foundation
import Observation

/// Whether the screen is covered right now, for the life of the app.
@MainActor
@Observable
public final class AppLockController {
    public private(set) var state: AppLockState

    @ObservationIgnored private let authenticator: any DeviceAuthenticator
    @ObservationIgnored private let reason: String

    public init(isEnabled: Bool, authenticator: any DeviceAuthenticator, reason: String) {
        self.authenticator = authenticator
        self.reason = reason
        // A passcode removed in iOS would otherwise leave the app locked for good, and the library out of reach.
        state = AppLockState(isEnabled: isEnabled && authenticator.isAvailable)
    }

    public var canLock: Bool {
        authenticator.isAvailable
    }

    public func setEnabled(_ enabled: Bool) async -> Bool {
        // Proves the person can open it again, and that the one turning it off is the owner.
        guard authenticator.isAvailable, await authenticator.authenticate(reason: reason) else { return false }
        state.setEnabled(enabled)
        UserDefaults.standard.set(enabled, forKey: AppLockPreferences.enabledKey)
        return true
    }

    /// For erasing everything, where the preference is already gone.
    public func forgetLock() {
        state.setEnabled(false)
    }

    public func becameInactive() {
        state.becameInactive()
    }

    public func enteredBackground() {
        state.enteredBackground()
    }

    public func becameActive() {
        if state.becameActive() {
            Task { await authenticate() }
        }
    }

    public func unlock() {
        if state.requestUnlock() {
            Task { await authenticate() }
        }
    }

    private func authenticate() async {
        await state.finishAuthentication(success: authenticator.authenticate(reason: reason))
    }
}
