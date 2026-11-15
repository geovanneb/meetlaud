import Localization
import SwiftUI

/// Consent, permission, and recovery messages, attached once at the root of the app.
public struct RecorderPrompts: ViewModifier {
    @Bindable private var controller: RecordingController
    @Environment(\.openURL) private var openURL

    public init(controller: RecordingController) {
        self.controller = controller
    }

    public func body(content: Content) -> some View {
        content
            .alert(L10n.Recorder.consentTitle, isPresented: $controller.showsConsent) {
                Button(L10n.Recorder.consentAccept) { controller.acceptConsent() }
                Button(L10n.Common.cancel, role: .cancel) {}
            } message: {
                Text(L10n.Recorder.consentMessage)
            }
            .alert(L10n.Recorder.permissionTitle, isPresented: $controller.showsPermissionDenied) {
                Button(L10n.Recorder.openSettings) {
                    if let url = URL(string: "app-settings:") {
                        openURL(url)
                    }
                }
                Button(L10n.Common.cancel, role: .cancel) {}
            } message: {
                Text(L10n.Recorder.permissionMessage)
            }
            .alert(L10n.Recorder.startFailed, isPresented: $controller.showsStartFailure) {
                Button(L10n.Common.ok, role: .cancel) {}
            }
            .alert(
                L10n.Recorder.recoveredTitle,
                isPresented: Binding(
                    get: { controller.recoveredCount > 0 },
                    set: {
                        if !$0 {
                            controller.dismissRecoveryNotice()
                        }
                    },
                ),
            ) {
                Button(L10n.Common.ok, role: .cancel) {}
            } message: {
                Text(L10n.Recorder.recoveredMessage)
            }
    }
}
