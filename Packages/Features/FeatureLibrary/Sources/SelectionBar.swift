import DesignSystem
import Domain
import Localization
import SwiftUI

struct MoveMenu: View {
    let folders: [Folder]
    let onMove: (FolderID?) -> Void

    var body: some View {
        Menu {
            Button(L10n.Library.recordings) { onMove(nil) }
            ForEach(folders) { folder in
                Button(folder.name) { onMove(folder.id) }
            }
        } label: {
            // The target only matters in the selection bar. In a context menu iOS draws the row itself.
            Label(L10n.Library.move, systemImage: "folder")
                .tappableTarget()
        }
    }
}

/// Where one recording goes. It is the same list as everywhere else, with the current place marked.
struct MoveSheet: View {
    let recording: Recording
    let folders: [Folder]
    let onMove: (FolderID?) -> Void

    var body: some View {
        ChoiceSheet(
            title: L10n.Library.move,
            closeLabel: L10n.Common.close,
            choices: [Choice(FolderID?.none, title: L10n.Library.recordings, symbol: "mic")]
                + folders.map { Choice(FolderID?.some($0.id), title: $0.name, symbol: "folder") },
            selection: Binding(get: { recording.folderID }, set: { onMove($0) }),
        )
    }
}

/// Actions for the recordings selected in the Library.
struct SelectionBar: View {
    let ids: [RecordingID]
    let library: LibraryController
    let onMove: (FolderID?) -> Void
    let onFinish: () -> Void

    var body: some View {
        HStack(spacing: Spacing.large) {
            MoveMenu(folders: library.folders, onMove: onMove)
            Spacer()
            Button {
                Task { try? await library.service.merge(ids) }
                onFinish()
            } label: {
                Label(L10n.Library.merge, systemImage: "arrow.trianglehead.merge")
                    .tappableTarget()
            }
            .disabled(ids.count < 2)
            .accessibilityIdentifier("library.merge")
            Spacer()
            Button(role: .destructive) {
                Task { try? await library.service.trash(ids) }
                onFinish()
            } label: {
                Label(L10n.Library.moveToTrash, systemImage: "trash")
                    .tappableTarget()
            }
            .accessibilityIdentifier("library.trashSelected")
        }
        .labelStyle(.iconOnly)
        .font(.dsIcon)
        .disabled(ids.isEmpty)
        // The targets are 44 points tall, so the bar needs less padding of its own to keep its height.
        .padding(.horizontal, Spacing.large)
        .padding(.vertical, Spacing.xSmall)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, Spacing.medium)
        .padding(.bottom, Spacing.small)
    }
}
