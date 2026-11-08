import Localization
import Testing

struct L10nTests {
    /// A missing key would return the key itself, such as "nav.home".
    @Test func `keys resolve to real text`() {
        let values = [
            L10n.Nav.home, L10n.Nav.library, L10n.Nav.ask, L10n.Nav.tools,
            L10n.Nav.settings, L10n.Nav.help, L10n.Nav.openMenu, L10n.Nav.closeMenu,
            L10n.Home.record, L10n.Home.meetingNotes, L10n.Home.emptyTitle,
            L10n.Home.emptyMessage, L10n.Home.askPlaceholder,
            L10n.Common.comingSoon, L10n.Common.comingSoonMessage,
        ]
        for value in values {
            #expect(!value.isEmpty)
            let looksLikeKey = value.contains(".") && !value.contains(" ")
            #expect(!looksLikeKey, "Unresolved key: \(value)")
        }
    }

    @Test func `the catalog is actually loaded`() {
        #expect(L10n.Nav.home == "Home")
    }
}
