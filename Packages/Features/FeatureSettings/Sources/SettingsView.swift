import AppRouting
import DesignSystem
import Domain
import Localization
import SwiftUI

public struct SettingsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @AppStorage(ThemePreferences.key) private var theme = AppTheme.system.rawValue
    @State private var isChoosingTheme = false

    public init() {}

    public var body: some View {
        List {
            Section(title: L10n.Settings.workspace) {
                row(L10n.Settings.preferences, symbol: "slider.horizontal.3", route: .preferences)
                row(L10n.Models.title, symbol: "cpu", route: .modelSettings)
                row(L10n.People.title, symbol: "person.2", route: .people)
                row(L10n.System.storageTitle, symbol: "externaldrive", route: .storage)
            }
            .listSectionSeparator(.hidden, edges: .top)
            Section(title: L10n.System.general) {
                row(L10n.System.notificationsTitle, symbol: "bell", route: .notifications)
                themeRow
                languageRow
            }
            .listSectionSeparator(.hidden, edges: .top)
            Section(title: L10n.Settings.privacy) {
                row(L10n.System.privacyTitle, symbol: "lock.shield", route: .privacy)
                row(L10n.Models.networkActivity, symbol: "network", route: .networkActivity)
            }
            .listSectionSeparator(.hidden, edges: .top)
            Section(title: L10n.Nav.help) {
                row(L10n.System.helpCenter, symbol: "questionmark.circle", route: .helpCenter)
                row(L10n.System.about, symbol: "info.circle", route: .about)
                row(L10n.System.licenses, symbol: "doc.plaintext", route: .licenses)
            }
            .listSectionSeparator(.hidden, edges: .top)
        }
        .screenList()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.Nav.settings)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $isChoosingTheme) {
            ChoiceSheet(
                title: L10n.System.themeTitle,
                closeLabel: L10n.Common.close,
                choices: AppTheme.allCases.map {
                    Choice($0.rawValue, title: $0.title, symbol: $0.symbol, identifier: "theme.\($0.rawValue)")
                },
                selection: $theme,
            )
        }
        .accessibilityIdentifier("screen.settings")
    }

    private var themeRow: some View {
        Button {
            isChoosingTheme = true
        } label: {
            SettingsRowLabel(
                L10n.System.themeTitle,
                symbol: "circle.lefthalf.filled",
                value: AppTheme(rawValue: theme)?.title,
            )
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("settings.theme")
    }

    /// iOS keeps each app's language in Settings, and that is the one place it should change.
    private var languageRow: some View {
        Button {
            if let url = URL(string: "app-settings:") {
                openURL(url)
            }
        } label: {
            SettingsRowLabel(L10n.System.language, symbol: "globe")
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("settings.language")
    }

    private func row(_ title: String, symbol: String, route: AppRoute) -> some View {
        Button {
            router.push(route)
        } label: {
            SettingsRowLabel(title, symbol: symbol)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("settings.\(route.identifier)")
    }
}

private extension AppTheme {
    var title: String {
        switch self {
        case .system: L10n.System.themeSystem
        case .light: L10n.System.themeLight
        case .dark: L10n.System.themeDark
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

private extension AppRoute {
    var identifier: String {
        switch self {
        case .modelSettings: "models"
        case .preferences: "preferences"
        case .networkActivity: "network"
        case .people: "people"
        case .storage: "storage"
        case .notifications: "notifications"
        case .privacy: "privacy"
        case .about: "about"
        case .licenses: "licenses"
        case .helpCenter: "help"
        default: "other"
        }
    }
}
