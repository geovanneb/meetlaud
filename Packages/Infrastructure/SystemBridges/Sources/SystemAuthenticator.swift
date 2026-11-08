import Domain
import LocalAuthentication

/// Face ID, Touch ID, or the passcode. iOS picks and draws it, and nothing about it reaches the app.
public struct SystemAuthenticator: DeviceAuthenticator {
    public init() {}

    public var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    public func authenticate(reason: String) async -> Bool {
        await (try? LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
