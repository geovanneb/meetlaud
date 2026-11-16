import DesignSystem
import Domain
import FeatureShared
import Localization
import SwiftUI

public struct TrashView: View {
    private let library: LibraryController
    @State private var isConfirmingEmpty = false

    public init(library: LibraryController) {
        self.library = library
    }

    public var body: some View {
        Group {
            if library.trashed.isEmpty {
                EmptyState(
                    title: L10n.Library.trashEmptyTitle,
                    message: L10n.Library.trashNotice,
                    symbol: "trash",
                )
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.Library.trash)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !library.trashed.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.Library.emptyTrash) { isConfirmingEmpty = true }
                        .accessibilityIdentifier("trash.empty")
                }
            }
        }
        .confirmationDialog(
            L10n.Library.emptyTrashConfirm,
            isPresented: $isConfirmingEmpty,
            titleVisibility: .visible,
        ) {
            Button(L10n.Library.emptyTrash, role: .destructive) {
                Task { try? await library.service.emptyTrash() }
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.trash")
    }

    private var list: some View {
        List {
            Section {
                ForEach(library.trashed) { recording in
                    RecordingRow(recording: recording)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .leading) {
                            Button(L10n.Library.restore, systemImage: "arrow.uturn.backward") {
                                Task { try? await library.service.restore([recording.id]) }
                            }
                            .tint(.dsAction)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(L10n.Library.delete, systemImage: "trash", role: .destructive) {
                                Task { try? await library.service.deleteForever([recording.id]) }
                            }
                        }
                        .contextMenu {
                            Button(L10n.Library.restore, systemImage: "arrow.uturn.backward") {
                                Task { try? await library.service.restore([recording.id]) }
                            }
                        }
                }
            } footer: {
                Text(L10n.Library.trashNotice)
                    .foregroundStyle(Color.dsSecondaryText)
            }
        }
        .screenList()
    }
}
