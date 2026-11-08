import Connectors
import SwiftUI

/// A connector that brings its own screens. Apart from `Connectors` so that a connector with no interface, and the
/// contract itself, stay free of SwiftUI.
public protocol ConnectorWithSettings: Connector {
    @MainActor func settingsView() -> AnyView
}
