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
                        // Which model takes the most, at a glance, before reading the rows.
                        VStack(alignment: .leading, spacing: Spacing.compact) {
                            Text(L10n.Models.storageTotal(installed.reduce(Int64(0)) { $0 + $1.totalBytes }.fileSize))
                                .font(.dsHeading)
                                .foregroundStyle(Color.dsPrimaryText)
                            UsageBar(parts: installed.map {
                                UsagePart(
                                    id: $0.id, title: $0.displayName, value: $0.totalBytes,
                                    formatted: $0.totalBytes.fileSize,
                                )
                            }, showsLegend: false)
                        }
                        .padding(.vertical, Spacing.small)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("models.storageUsage")
                    }
                    .listRowBackground(Color.clear)
                    Section {
                        ForEach(Array(installed.enumerated()), id: \.element.id) { index, model in
                            HStack(spacing: Spacing.small) {
                                UsageDot(index: index)
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
    @State private var isConfirmingClear = false
    /// After a clear, "nothing has left this device" would no longer be true.
    @AppStorage("network.clearedAt") private var clearedAt: Double = 0

    public init(controller: ModelsController) {
        self.controller = controller
    }

    public var body: some View {
        Group {
            if controller.networkLog.isEmpty {
                EmptyState(
                    title: clearedAt > 0 ? L10n.Models.networkClearedTitle : L10n.Models.networkEmptyTitle,
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
        .toolbar {
            if !controller.networkLog.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.Models.clearNetworkLog) { isConfirmingClear = true }
                        .accessibilityIdentifier("network.clear")
                }
            }
        }
        .confirmationDialog(
            L10n.Models.clearNetworkLogConfirm,
            isPresented: $isConfirmingClear,
            titleVisibility: .visible,
        ) {
            Button(L10n.Models.clearNetworkLog, role: .destructive) {
                clearedAt = Date().timeIntervalSince1970
                Task { await controller.clearNetworkLog() }
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        }
        .task { await controller.refreshNetworkLog() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.network")
    }
}
