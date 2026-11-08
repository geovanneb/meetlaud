import DesignSystem
import Domain
import Localization
import SwiftUI

/// Choose the calendars that Upcoming, Calendar view, and widgets read. A work account comes through iOS, never
/// through a sign-in here.
public struct CalendarsView: View {
    private let model: CalendarsModel
    @Environment(\.openURL) private var openURL

    public init(model: CalendarsModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section {
                Toggle(L10n.Calendars.use, isOn: Binding(
                    get: { model.isUsing },
                    set: { isOn in Task { await model.setUsing(isOn) } },
                ))
                .accessibilityIdentifier("calendars.use")
            } footer: {
                Text(model.isUsing ? L10n.Calendars.revoke : L10n.Calendars.useNote)
                    .foregroundStyle(Color.dsSecondaryText)
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)
            if model.access == .denied {
                Section {
                    Text(L10n.Calendars.denied)
                    Button(L10n.Calendars.openSettings, action: openAppSettings)
                        .foregroundStyle(Color.dsAction)
                        .accessibilityIdentifier("calendars.openSettings")
                }
                .listRowBackground(Color.clear)
            }
            if model.isUsing {
                calendars
                Section(title: L10n.Calendars.addTitle) {
                    Text(L10n.Calendars.addHelp)
                        .font(.dsMeta)
                        .foregroundStyle(Color.dsSecondaryText)
                }
                .listRowBackground(Color.clear)
            }
        }
        .screenList()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.Calendars.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.calendars")
    }

    @ViewBuilder private var calendars: some View {
        if model.accounts?.isEmpty == true {
            Text(L10n.Calendars.none)
                .foregroundStyle(Color.dsSecondaryText)
                .listRowBackground(Color.clear)
        }
        ForEach(model.accounts ?? []) { account in
            Section(title: account.name) {
                ForEach(account.calendars) { calendar in
                    Toggle(isOn: Binding(
                        get: { model.isShown(calendar) },
                        set: { model.setShown($0, for: calendar) },
                    )) {
                        // A row, not a `Label`: the audit reports a label with a drawn icon as clipped text.
                        HStack(spacing: Spacing.small) {
                            Circle()
                                .fill(tint(calendar))
                                .frame(width: 12, height: 12)
                                .accessibilityHidden(true)
                            Text(calendar.title)
                        }
                    }
                    // Several accounts can each have a calendar named "Calendar": say which one.
                    .accessibilityLabel([calendar.title, account.name].joined(separator: ", "))
                    .accessibilityIdentifier("calendars.item.\(calendar.id)")
                }
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)
        }
    }

    private func tint(_ calendar: CalendarSource) -> Color {
        guard let tint = calendar.tint else { return Color.dsSecondaryText }
        return Color(red: tint.red, green: tint.green, blue: tint.blue)
    }

    private func openAppSettings() {
        if let url = URL(string: "app-settings:") {
            openURL(url)
        }
    }
}
