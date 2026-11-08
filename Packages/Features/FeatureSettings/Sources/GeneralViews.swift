import DesignSystem
import Domain
import Localization
import SwiftUI

public struct NotificationsView: View {
    private let controller: SystemController
    @AppStorage(NotificationPreferences.transcriptReadyKey) private var transcriptReady = false
    @AppStorage(NotificationPreferences.eventRemindersKey) private var eventReminders = false

    public init(controller: SystemController) {
        self.controller = controller
    }

    public var body: some View {
        List {
            Section {
                Toggle(L10n.System.notifyTranscript, isOn: guarded($transcriptReady))
                    .accessibilityIdentifier("notifications.transcript")
                Toggle(L10n.System.notifyEvents, isOn: guarded($eventReminders))
                    .accessibilityIdentifier("notifications.events")
            } footer: {
                Text(L10n.System.notifyNote)
                    .foregroundStyle(Color.dsSecondaryText)
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)
        }
        .screenList()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.System.notificationsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.notifications")
    }

    /// Asks iOS for permission at the moment it is needed, and stays off if the answer is no.
    private func guarded(_ value: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue },
            set: { wanted in
                guard wanted else {
                    value.wrappedValue = false
                    return
                }
                Task { value.wrappedValue = await controller.requestNotificationAccess() }
            },
        )
    }
}

public struct AboutView: View {
    private let version: String

    public init(version: String) {
        self.version = version
    }

    public var body: some View {
        List {
            Section {
                LabeledContent(L10n.System.version, value: version)
                LabeledContent(L10n.System.license, value: "Apache-2.0")
            } footer: {
                Text(L10n.System.aboutNote)
                    .foregroundStyle(Color.dsSecondaryText)
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)
        }
        .screenList()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.System.about)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.about")
    }
}

public struct LicensesView: View {
    private let blocks: [MarkdownBlock]

    public init(text: String) {
        blocks = MarkdownBlock.parse(text)
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.compact) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .padding(Spacing.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.System.licenses)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.licenses")
    }

    @ViewBuilder private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case let .title(text):
            Text(text.inlineMarkdown)
                .font(.dsPageTitle)
                .accessibilityAddTraits(.isHeader)
        case let .heading(text):
            Text(text.inlineMarkdown)
                .font(.dsHeading)
                .padding(.top, Spacing.compact)
                .accessibilityAddTraits(.isHeader)
        case let .paragraph(text):
            Text(text.inlineMarkdown)
                .font(.dsMeta)
                .foregroundStyle(Color.dsSecondaryText)
                .textSelection(.enabled)
        case let .bullet(text):
            Text(text.inlineMarkdown)
                .font(.dsMeta)
                .padding(Spacing.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.dsSurface, in: .rect(cornerRadius: Radius.medium))
                .textSelection(.enabled)
        case let .table(rows):
            table(rows)
        }
    }

    private func table(_ rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider()
                }
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text((row.first ?? "").inlineMarkdown)
                        .font(.dsRowTitle)
                    ForEach(Array(row.dropFirst().enumerated()), id: \.offset) { _, cell in
                        Text(cell.inlineMarkdown)
                            .font(.dsMeta)
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.compact)
                .accessibilityElement(children: .combine)
            }
        }
        .background(Color.dsSurface, in: .rect(cornerRadius: Radius.medium))
    }
}
