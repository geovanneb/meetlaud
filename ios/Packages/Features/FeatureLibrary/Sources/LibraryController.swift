import Domain
import FeatureShared
import Foundation
import Localization
import Observation

/// The state of the library, shared by its screens. There is one for the life of the app.
@MainActor
@Observable
public final class LibraryController {
    public private(set) var all: [Recording] = []
    public private(set) var folders: [Folder] = []
    public private(set) var isImporting = false
    public var showsFilePicker = false
    public var showsImportFailure = false

    public var sort: RecordingSort {
        didSet { defaults.set(sort.rawValue, forKey: RecordingSort.storageKey) }
    }

    @ObservationIgnored public let service: LibraryService
    @ObservationIgnored private let store: any RecordingStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    public init(service: LibraryService, store: any RecordingStore, defaults: UserDefaults = .standard) {
        self.service = service
        self.store = store
        self.defaults = defaults
        sort = defaults.string(forKey: RecordingSort.storageKey).flatMap(RecordingSort.init) ?? .newest
        tasks.append(Task { [weak self] in
            for await recordings in store.observeRecordings() {
                self?.all = recordings
            }
        })
        tasks.append(Task { [weak self] in
            for await folders in store.observeFolders() {
                self?.folders = folders
            }
        })
        Task { _ = try? await service.purgeExpiredTrash() }
    }

    deinit {
        tasks.forEach { $0.cancel() }
    }

    public var active: [Recording] {
        sort.sorted(all.filter { $0.deletedAt == nil && $0.status == .ready })
    }

    public var trashed: [Recording] {
        all.filter { $0.deletedAt != nil }.sorted { ($0.deletedAt ?? .now) > ($1.deletedAt ?? .now) }
    }

    /// `nil` is the main Recordings list.
    public func recordings(in folder: FolderID?) -> [Recording] {
        active.filter { $0.folderID == folder }
    }

    func search(_ query: String) async -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return await (try? store.search(trimmed)) ?? []
    }

    // MARK: - Import

    public func presentFilePicker() {
        showsFilePicker = true
    }

    /// Handles files from the picker and from "Open in Meetlaud" in other apps.
    public func importFiles(_ urls: [URL]) {
        Task {
            isImporting = true
            defer { isImporting = false }
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let title = url.deletingPathExtension().lastPathComponent
                if await (try? service.importAudio(from: url, title: title)) == nil {
                    showsImportFailure = true
                }
            }
        }
    }
}
