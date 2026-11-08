import DesignSystem
import Domain
import Localization
import SwiftUI

struct StorageView: View {
    let controller: ModelsController

    private var installed: [ModelDescriptor] {
        guard let snapshot = controller.snapshot else { return [] }
        var seen: Set<String> = []
        return snapshot.fits.values.joined().map(\.model)
            .filter { snapshot.isInstalled($0.id) && !$0.isSystemManaged && seen.insert($0.id).inserted }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    var body: some View {
        Group {
            if installed.isEmpty {
                EmptyState(
                    title: L10n.Models.noModels,
                    message: L10n.Models.storageNote,
                    symbol: "internaldrive",
                )
            } else {
                List {
                    Section {
                        ForEach(installed) { model in
                            HStack {
                                Text(model.displayName)
                                Spacer()
                                Text(model.totalBytes.fileSize)
                                    .foregroundStyle(Color.dsSecondaryText)
                            }
                            .accessibilityElement(children: .combine)
                            .swipeActions {
                                Button(L10n.Library.delete, role: .destructive) { controller.remove(model.id) }
                            }
                        }
                    } footer: {
                        Text(L10n.Models.storageNote)
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                    .listRowBackground(Color.clear)
                }
                .screenList()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.Models.storage)
        .navigationBarTitleDisplayMode(.inline)
    }
}

public struct NetworkActivityView: View {
    private let controller: ModelsController

    public init(controller: ModelsController) {
        self.controller = controller
    }

    public var body: some View {
        Group {
            if controller.networkLog.isEmpty {
                EmptyState(
                    title: L10n.Models.networkEmptyTitle,
                    message: L10n.Models.networkNote,
                    symbol: "checkmark.shield",
                )
            } else {
                List {
                    Section {
                        ForEach(controller.networkLog) { entry in
                            RowLabel(entry.host, detail: [
                                entry.modelID,
                                entry.bytes.fileSize,
                                entry.date.formatted(date: .abbreviated, time: .shortened),
                            ].joined(separator: " · "))
                                .accessibilityElement(children: .combine)
                        }
                    } footer: {
                        Text(L10n.Models.networkNote)
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                    .listRowBackground(Color.clear)
                }
                .screenList()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.Models.networkActivity)
        .navigationBarTitleDisplayMode(.inline)
        .task { await controller.refreshNetworkLog() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.network")
    }
}
