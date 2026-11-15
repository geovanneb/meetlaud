import DesignSystem
import Domain
import Localization
import SwiftUI

/// Names and terms the transcript should spell a certain way.
public struct VocabularyView: View {
    @State private var entries = VocabularyPreferences.load()
    @State private var editing: VocabularyEntry?
    private let folders: [Folder]

    public init(folders: [Folder] = []) {
        self.folders = folders
    }

    public var body: some View {
        Group {
            if entries.isEmpty {
                EmptyState(
                    title: L10n.Vocabulary.title,
                    message: L10n.Vocabulary.hint,
                    symbol: "character.book.closed",
                )
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.Vocabulary.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.Vocabulary.add, systemImage: "plus") {
                    editing = VocabularyEntry(heard: "", written: "")
                }
                .accessibilityIdentifier("vocabulary.add")
            }
        }
        .sheet(item: $editing) { entry in
            VocabularyEditor(entry: entry, folders: folders, onSave: save)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.vocabulary")
    }

    private var list: some View {
        List {
            ForEach(groups, id: \.folder) { group in
                Section {
                    ForEach(group.entries) { entry in
                        Button { editing = entry } label: {
                            RowLabel(entry.written, detail: entry.heard)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(L10n.Library.delete, systemImage: "trash", role: .destructive) { delete(entry) }
                        }
                    }
                    .listRowBackground(Color.clear)
                } header: {
                    if groups.count > 1 || group.folder != nil {
                        Text(title(of: group.folder))
                    }
                } footer: {
                    if group.folder == groups.last?.folder {
                        Text(L10n.Vocabulary.hint)
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                }
                .listSectionSeparator(.hidden, edges: .top)
            }
        }
        .screenList()
    }

    /// Words for every recording first, then each folder in the order of the library.
    private var groups: [(folder: FolderID?, entries: [VocabularyEntry])] {
        let known = Set(folders.map(\.id))
        // A word whose folder was deleted keeps working everywhere, rather than vanishing.
        let global = entries.filter { $0.folderID.map { !known.contains($0) } ?? true }
        var result: [(folder: FolderID?, entries: [VocabularyEntry])] = global.isEmpty ? [] : [(nil, global)]
        for folder in folders {
            let own = entries.filter { $0.folderID == folder.id }
            if !own.isEmpty {
                result.append((folder.id, own))
            }
        }
        return result
    }

    private func title(of folder: FolderID?) -> String {
        folder.flatMap { id in folders.first { $0.id == id }?.name } ?? L10n.Vocabulary.everywhere
    }

    private func save(_ entry: VocabularyEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        VocabularyPreferences.save(entries)
    }

    private func delete(_ entry: VocabularyEntry) {
        entries.removeAll { $0.id == entry.id }
        VocabularyPreferences.save(entries)
    }
}

private struct VocabularyEditor: View {
    @State var entry: VocabularyEntry
    let folders: [Folder]
    let onSave: (VocabularyEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.Vocabulary.heard, text: $entry.heard)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("vocabulary.heard")
                TextField(L10n.Vocabulary.written, text: $entry.written)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("vocabulary.written")
                if !folders.isEmpty {
                    Picker(L10n.Vocabulary.appliesTo, selection: $entry.folderID) {
                        Text(L10n.Vocabulary.everywhere).tag(FolderID?.none)
                        ForEach(folders) { folder in
                            Text(folder.name).tag(Optional(folder.id))
                        }
                    }
                    .accessibilityIdentifier("vocabulary.folder")
                }
            }
            .navigationTitle(L10n.Vocabulary.add)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save) {
                        onSave(entry)
                        dismiss()
                    }
                    .disabled(!entry.isValid)
                    .accessibilityIdentifier("vocabulary.save")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
