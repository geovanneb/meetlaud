import AppRouting
import DesignSystem
import Domain
import FeatureShared
import Localization
import SwiftUI

public struct LibraryView: View {
    @Bindable private var library: LibraryController
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Shows each meeting's transcription where it is listed, as Home does.
    private let center: TranscriptionCenter?

    public init(library: LibraryController, center: TranscriptionCenter? = nil) {
        self.library = library
        self.center = center
    }

    @State private var isSelecting = false
    @State private var selection: Set<RecordingID> = []
    @State private var expanded: Set<FolderID> = []
    @State private var isMainExpanded = true
    @State private var isNamingFolder = false
    @State private var renamingFolder: Folder?
    @State private var renamingRecording: Recording?
    @State private var movingRecording: Recording?
    @State private var name = ""

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .navigationTitle(L10n.Nav.library)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) {
                Group {
                    if isSelecting {
                        SelectionBar(
                            ids: Array(selection),
                            library: library,
                            onMove: { move(Array(selection), to: $0) },
                            onFinish: endSelection,
                        )
                        .riseTransition()
                    }
                }
                .motion(Motion.standard, value: isSelecting)
            }
            .modifier(NamePrompt(
                title: L10n.Library.newFolder,
                isPresented: $isNamingFolder,
                name: $name,
            ) {
                let folderName = name
                Task { try? await library.service.createFolder(named: folderName) }
            })
            .modifier(NamePrompt(
                title: L10n.Library.rename,
                isPresented: isRenaming,
                name: $name,
                onSave: saveRename,
            ))
            .sheet(item: $movingRecording) { recording in
                MoveSheet(recording: recording, folders: library.folders) { move([recording.id], to: $0) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.library")
    }

    private var isRenaming: Binding<Bool> {
        Binding(
            get: { renamingFolder != nil || renamingRecording != nil },
            set: {
                if !$0 {
                    renamingFolder = nil
                    renamingRecording = nil
                }
            },
        )
    }

    private func saveRename() {
        let newName = name
        if let renamingFolder {
            Task { try? await library.service.rename(renamingFolder, to: newName) }
        } else if let renamingRecording {
            Task { try? await library.service.rename(renamingRecording.id, to: newName) }
        }
    }

    @ViewBuilder private var content: some View {
        if isSelecting {
            List(library.active, selection: $selection) { recording in
                RecordingRow(recording: recording, progress: center?.progress[recording.id])
                    .listRowBackground(Color.clear)
                    .tag(recording.id)
            }
            .screenList()
            .environment(\.editMode, .constant(.active))
        } else {
            // Grouped once per update: asking the library per folder sorted every recording several times a folder.
            let groups = Dictionary(grouping: library.active, by: \.folderID)
            List {
                Section {
                    mainFolder(groups[FolderID?.none] ?? [])
                    ForEach(library.folders) { folder in
                        folderRow(folder, recordings: groups[folder.id] ?? [])
                    }
                } header: {
                    header
                }
                .listRowBackground(Color.clear)
                .listSectionSeparator(.hidden)
            }
            .screenList()
        }
    }

    private var header: some View {
        HStack {
            Text(L10n.Library.myFiles)
                .font(.dsPageTitle)
                .foregroundStyle(Color.dsPrimaryText)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                name = ""
                isNamingFolder = true
            } label: {
                Label(L10n.Library.newFolder, systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .tappableTarget()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dsSecondaryText)
            .accessibilityIdentifier("library.newFolder")
        }
    }

    private func mainFolder(_ recordings: [Recording]) -> some View {
        DisclosureGroup(isExpanded: $isMainExpanded.animation(disclosure)) {
            rows(recordings)
        } label: {
            folderLabel(name: L10n.Library.recordings, count: recordings.count, symbol: "mic")
                .dropDestination(for: String.self) { ids, _ in drop(ids, into: nil) }
        }
    }

    private func folderRow(_ folder: Folder, recordings: [Recording]) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(folder.id) },
            set: { isOn in
                withAnimation(disclosure) {
                    if isOn {
                        expanded.insert(folder.id)
                    } else {
                        expanded.remove(folder.id)
                    }
                }
            },
        )) {
            rows(recordings)
            if recordings.isEmpty {
                Text(L10n.Library.folderEmpty)
                    .font(.dsNote)
                    .foregroundStyle(Color.dsSecondaryText)
                    .listRowBackground(Color.clear)
            }
        } label: {
            folderLabel(name: folder.name, count: recordings.count, symbol: "folder")
                .dropDestination(for: String.self) { ids, _ in drop(ids, into: folder.id) }
        }
        .swipeActions {
            Button(L10n.Library.delete, systemImage: "trash", role: .destructive) {
                Task { try? await library.service.delete(folder) }
            }
            Button(L10n.Library.rename, systemImage: "pencil") {
                name = folder.name
                renamingFolder = folder
            }
            Button(L10n.Ask.aboutFolder, systemImage: "sparkles") {
                router.push(.askFolder(folder.id))
            }
        }
    }

    private func rows(_ recordings: [Recording]) -> some View {
        ForEach(recordings) { recording in
            Button {
                router.push(.recording(recording.id, at: nil))
            } label: {
                RecordingRow(recording: recording, progress: center?.progress[recording.id])
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .draggable(recording.id.rawValue.uuidString)
            .swipeActions(edge: .leading) {
                Button(L10n.Library.move, systemImage: "folder") { movingRecording = recording }
                    .tint(.dsAction)
            }
            .swipeActions {
                Button(L10n.Library.moveToTrash, systemImage: "trash", role: .destructive) {
                    Task { try? await library.service.trash([recording.id]) }
                }
            }
            .contextMenu {
                Button(L10n.Library.rename, systemImage: "pencil") {
                    name = recording.title
                    renamingRecording = recording
                }
                MoveMenu(folders: library.folders) { move([recording.id], to: $0) }
                Button(L10n.Library.moveToTrash, systemImage: "trash", role: .destructive) {
                    Task { try? await library.service.trash([recording.id]) }
                }
            }
        }
    }

    private func drop(_ ids: [String], into folder: FolderID?) {
        let recordings = ids.compactMap(RecordingID.init(string:))
        guard !recordings.isEmpty else { return }
        Task { try? await library.service.move(recordings, to: folder) }
    }

    private func move(_ ids: [RecordingID], to folder: FolderID?) {
        Task { try? await library.service.move(ids, to: folder) }
        endSelection()
    }

    private func endSelection() {
        isSelecting = false
        selection = []
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.Common.done, action: endSelection)
                    .accessibilityIdentifier("library.done")
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L10n.Library.search, systemImage: "magnifyingglass") {
                    router.push(.search)
                }
                .accessibilityIdentifier("library.search")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu(L10n.Library.more, systemImage: "ellipsis") {
                    Button(L10n.Library.select, systemImage: "checkmark.circle") { isSelecting = true }
                    Picker(selection: $library.sort) {
                        ForEach(RecordingSort.allCases, id: \.self) { sort in
                            Text(sort.title).tag(sort)
                        }
                    } label: {
                        Label(L10n.Library.sortBy, systemImage: "arrow.up.arrow.down")
                    }
                    .pickerStyle(.menu)
                    Divider()
                    Button(L10n.Library.trash, systemImage: "trash") { router.push(.trash) }
                }
                .accessibilityIdentifier("library.more")
            }
        }
    }
}

private extension LibraryView {
    func folderLabel(name: String, count: Int, symbol: String) -> some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: symbol)
                .foregroundStyle(Color.dsSecondaryText)
                .frame(width: Spacing.large)
                .accessibilityHidden(true)
            RowLabel(name, detail: L10n.Library.itemCount(count))
        }
        .padding(.vertical, Spacing.xSmall)
        .accessibilityElement(children: .combine)
    }

    /// Opening and closing a folder slides its rows in and out, so the person sees where they came from. The
    /// change has to be animated where it happens: a list does not animate a disclosure by itself.
    var disclosure: Animation {
        reduceMotion ? Motion.reduced : Motion.standard
    }
}
