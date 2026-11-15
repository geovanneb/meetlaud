import Foundation

public enum LibraryError: Error, Equatable {
    case nothingToMerge
    case recordingNotFound
}

/// What a person can do to their recordings once they exist.
public struct LibraryService: Sendable {
    /// Trashed recordings stay this long, so that a mistake can be undone.
    public static let trashRetention: TimeInterval = 30 * 24 * 60 * 60

    private let store: any RecordingStore
    private let files: any RecordingFiles
    private let audio: any AudioProcessor
    private let now: @Sendable () -> Date

    public init(
        store: any RecordingStore,
        files: any RecordingFiles,
        audio: any AudioProcessor,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.store = store
        self.files = files
        self.audio = audio
        self.now = now
    }

    // MARK: - Organize

    public func rename(_ id: RecordingID, to title: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var recording = try await store.recording(id) else { return }
        recording.title = trimmed
        try await store.update(recording)
    }

    public func move(_ ids: [RecordingID], to folder: FolderID?) async throws {
        try await edit(ids) { $0.folderID = folder }
    }

    @discardableResult
    public func createFolder(named name: String) async throws -> Folder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let folder = Folder(name: trimmed, createdAt: now())
        try await store.insert(folder)
        return folder
    }

    public func rename(_ folder: Folder, to name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var folder = folder
        folder.name = trimmed
        try await store.update(folder)
    }

    /// Recordings inside are kept, and return to the main list.
    public func delete(_ folder: Folder) async throws {
        try await store.delete(folder.id)
    }

    // MARK: - Trash

    public func trash(_ ids: [RecordingID]) async throws {
        let date = now()
        try await edit(ids) { $0.deletedAt = date }
    }

    public func restore(_ ids: [RecordingID]) async throws {
        try await edit(ids) { $0.deletedAt = nil }
    }

    public func deleteForever(_ ids: [RecordingID]) async throws {
        for id in ids {
            try await store.delete(id)
            try? files.removeAll(for: id)
        }
    }

    public func emptyTrash() async throws {
        try await deleteForever(store.trashedRecordings().map(\.id))
    }

    /// Runs at launch. Returns how many recordings were removed.
    @discardableResult
    public func purgeExpiredTrash() async throws -> Int {
        let limit = now().addingTimeInterval(-Self.trashRetention)
        let expired = try await store.trashedRecordings().filter { ($0.deletedAt ?? .distantFuture) < limit }
        try await deleteForever(expired.map(\.id))
        return expired.count
    }

    // MARK: - Import

    /// Copies audio from outside the app into a new recording.
    public func importAudio(from source: URL, title: String) async throws -> Recording {
        let id = RecordingID()
        try files.prepare(for: id)
        do {
            let duration = try await audio.importAudio(from: source, to: files.audioFile(for: id))
            let recording = Recording(id: id, title: title, createdAt: now(), duration: duration)
            try await store.insert(recording)
            return recording
        } catch {
            try? files.removeAll(for: id)
            throw error
        }
    }

    // MARK: - Merge

    /// Joins recordings in time order into a new one, and moves the originals to the trash, so nothing is lost.
    @discardableResult
    public func merge(_ ids: [RecordingID]) async throws -> Recording {
        var recordings: [Recording] = []
        for id in ids {
            guard let recording = try await store.recording(id) else { throw LibraryError.recordingNotFound }
            recordings.append(recording)
        }
        recordings.sort { $0.createdAt < $1.createdAt }
        guard recordings.count > 1, let first = recordings.first else { throw LibraryError.nothingToMerge }

        let id = RecordingID()
        try files.prepare(for: id)
        do {
            let duration = try await audio.merge(
                recordings.map { files.audioFile(for: $0.id) },
                to: files.audioFile(for: id),
            )
            let merged = Recording(
                id: id,
                title: first.title,
                createdAt: first.createdAt,
                duration: duration,
                folderID: first.folderID,
                attendees: recordings.flatMap(\.attendees).reduce(into: []) { names, name in
                    if !names.contains(name) {
                        names.append(name)
                    }
                },
            )
            try await store.insert(merged)
            try await copyMarkers(from: recordings, to: id)
            try await trash(recordings.map(\.id))
            return merged
        } catch {
            try? await store.delete(id)
            try? files.removeAll(for: id)
            throw error
        }
    }

    private func copyMarkers(from recordings: [Recording], to id: RecordingID) async throws {
        var offset: TimeInterval = 0
        for recording in recordings {
            for marker in try await store.markers(for: recording.id) {
                if let name = marker.attachment {
                    try files.copyAttachment(name, from: recording.id, to: id)
                }
                try await store.insert(Marker(
                    recordingID: id,
                    time: marker.time + offset,
                    kind: marker.kind,
                    text: marker.text,
                    attachment: marker.attachment,
                ))
            }
            offset += recording.duration
        }
    }

    private func edit(_ ids: [RecordingID], _ change: (inout Recording) -> Void) async throws {
        for id in ids {
            guard var recording = try await store.recording(id) else { continue }
            change(&recording)
            try await store.update(recording)
        }
    }
}
