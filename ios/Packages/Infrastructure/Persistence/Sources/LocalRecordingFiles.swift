import Domain
import Foundation

/// The app's folders. Everything stays out of iOS backup unless the user opts in (D-002).
public struct LocalRecordingFiles: RecordingFiles {
    public let root: URL

    /// `.complete` would block writes while the device is locked, which is when most recording happens.
    private static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    public init(root: URL) throws {
        self.root = root
        try Self.makeDirectory(root)
        try Self.excludeFromBackup(root)
    }

    public var databasePath: String {
        root.appending(path: "meetlaud.sqlite").path
    }

    public func segmentsDirectory(for id: RecordingID) throws -> URL {
        let url = folder(for: id).appending(path: "audio")
        try Self.makeDirectory(url)
        return url
    }

    public func audioFile(for id: RecordingID) -> URL {
        folder(for: id).appending(path: "recording.m4a")
    }

    public func attachmentsDirectory(for id: RecordingID) throws -> URL {
        let url = folder(for: id).appending(path: "attachments")
        try Self.makeDirectory(url)
        return url
    }

    public func prepare(for id: RecordingID) throws {
        try Self.makeDirectory(folder(for: id))
    }

    public func copyAttachment(_ name: String, from source: RecordingID, to destination: RecordingID) throws {
        try FileManager.default.copyItem(
            at: attachmentsDirectory(for: source).appending(path: name),
            to: attachmentsDirectory(for: destination).appending(path: name),
        )
    }

    public func removeSegments(for id: RecordingID) throws {
        try FileManager.default.removeItem(at: folder(for: id).appending(path: "audio"))
    }

    public func removeAll(for id: RecordingID) throws {
        try FileManager.default.removeItem(at: folder(for: id))
    }

    public func hasSegments(for id: RecordingID) -> Bool {
        let directory = folder(for: id).appending(path: "audio")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
        )) ?? []
        return files.contains { file in
            ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 1
        }
    }

    public func availableBytes() -> Int64 {
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private func folder(for id: RecordingID) -> URL {
        root.appending(path: "recordings").appending(path: id.rawValue.uuidString)
    }

    private static func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: protection],
        )
    }

    static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

extension LocalRecordingFiles: StorageManaging {
    private static func size(of url: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
        ) else { return 0 }
        return walker.compactMap { $0 as? URL }.reduce(0) { total, file in
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            return total + Int64(values?.isRegularFile == true ? values?.totalFileAllocatedSize ?? 0 : 0)
        }
    }

    public func usage() -> StorageUsage {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let database = names.filter { $0.hasPrefix("meetlaud.sqlite") }.reduce(Int64(0)) { total, name in
            let values = try? root.appending(path: name).resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            return total + Int64(values?.totalFileAllocatedSize ?? 0)
        }
        return StorageUsage(
            recordings: Self.size(of: root.appending(path: "recordings")),
            library: database,
            models: Self.size(of: root.appending(path: "models")),
            cache: Self.size(of: FileManager.default.temporaryDirectory),
            available: (try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                .volumeAvailableCapacityForImportantUsage,
        )
    }

    public func clearCache() {
        let temporary = FileManager.default.temporaryDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? []
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    public func setBackupIncluded(_ included: Bool) throws {
        var folder = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = !included
        try folder.setResourceValues(values)
        // The flag is per item, and a child can opt out of a parent that opted in.
        let models = root.appending(path: "models")
        if FileManager.default.fileExists(atPath: models.path) {
            try Self.excludeFromBackup(models)
        }
    }

    public func removeEverything() throws {
        let recordings = root.appending(path: "recordings")
        if FileManager.default.fileExists(atPath: recordings.path) {
            try FileManager.default.removeItem(at: recordings)
        }
        clearCache()
    }
}
