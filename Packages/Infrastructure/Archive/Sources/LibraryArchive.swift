import Domain
import Foundation

/// Moves a whole library to another device, as one password-protected file, with no cloud in between.
public struct LibraryArchive: LibraryArchiver {
    private static let databaseEntry = "database.sqlite"
    private static let recordingsFolder = "recordings"
    private static let copySize = 256 * 1024

    private let root: URL
    private let snapshots: any DatabaseSnapshots

    public init(root: URL, snapshots: any DatabaseSnapshots) {
        self.root = root
        self.snapshots = snapshots
    }

    public func export(
        to url: URL,
        password: String,
        includingVoicePrints: Bool,
        progress: @escaping @Sendable (Double) -> Void,
    ) async throws {
        let work = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        let database = work.appending(path: Self.databaseEntry)
        try await snapshots.writeSnapshot(to: database, includingVoicePrints: includingVoicePrints)

        var entries = [(name: Self.databaseEntry, url: database)]
        entries += recordingFiles()
        let total = max(1, entries.reduce(Int64(0)) { $0 + Self.size(of: $1.url) })
        var done: Int64 = 0

        let writer = try SealedWriter(url: url, password: password)
        for entry in entries {
            try Task.checkCancellation()
            try Self.write(entry.name, from: entry.url, to: writer) { copied in
                done += copied
                progress(Double(done) / Double(total))
            }
        }
        try writer.write(Self.encode(UInt32(0)))
        try writer.finish()
        progress(1)
    }

    public func restore(
        from url: URL,
        password: String,
        progress: @escaping @Sendable (Double) -> Void,
    ) async throws {
        let work = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        // Everything lands in a side folder first. A wrong password or a damaged file must leave the library as it was.
        try Self.extract(url, password: password, into: work, progress: progress)
        let database = work.appending(path: Self.databaseEntry)
        guard FileManager.default.fileExists(atPath: database.path) else { throw ArchiveError.damaged }

        try Task.checkCancellation()
        try await snapshots.restoreSnapshot(from: database)
        let live = root.appending(path: Self.recordingsFolder)
        try? FileManager.default.removeItem(at: live)
        let restored = work.appending(path: Self.recordingsFolder)
        if FileManager.default.fileExists(atPath: restored.path) {
            try FileManager.default.moveItem(at: restored, to: live)
        }
        progress(1)
    }

    private func scratchFolder() throws -> URL {
        let folder = root.appending(path: "archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func recordingFiles() -> [(name: String, url: URL)] {
        let folder = root.appending(path: Self.recordingsFolder)
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }
        let prefix = root.standardizedFileURL.path + "/"
        return walker.compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { (name: String($0.standardizedFileURL.path.dropFirst(prefix.count)), url: $0) }
    }

    private static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private static func encode(_ value: some FixedWidthInteger) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private static func decode<T: FixedWidthInteger>(_ data: Data, as _: T.Type = T.self) -> T {
        data.reduce(T(0)) { ($0 << 8) | T($1) }
    }

    private static func write(
        _ name: String,
        from url: URL,
        to writer: SealedWriter,
        copied: (Int64) -> Void,
    ) throws {
        let label = Data(name.utf8)
        try writer.write(encode(UInt32(label.count)) + label + encode(UInt64(size(of: url))))
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: copySize), !chunk.isEmpty {
            try Task.checkCancellation()
            try writer.write(chunk)
            copied(Int64(chunk.count))
        }
    }

    private static func extract(
        _ url: URL,
        password: String,
        into folder: URL,
        progress: @Sendable (Double) -> Void,
    ) throws {
        let reader = try SealedReader(url: url, password: password)
        defer { reader.close() }
        let total = max(1, size(of: url))
        var destinations = Set<String>()
        while true {
            try Task.checkCancellation()
            let length: UInt32 = try decode(reader.read(4))
            guard length > 0 else {
                try reader.requireEnd()
                return
            }
            guard length <= 4096, let name = try String(data: reader.read(Int(length)), encoding: .utf8) else {
                throw ArchiveError.damaged
            }
            let target = try destination(of: name, in: folder)
            guard destinations.insert(target.path).inserted else { throw ArchiveError.damaged }
            var remaining: UInt64 = try decode(reader.read(8))
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true,
            )
            FileManager.default.createFile(atPath: target.path, contents: nil)
            let output = try FileHandle(forWritingTo: target)
            defer { try? output.close() }
            while remaining > 0 {
                try Task.checkCancellation()
                let step = Int(min(remaining, UInt64(copySize)))
                try output.write(contentsOf: reader.read(step))
                remaining -= UInt64(step)
                progress(min(0.95, Double(reader.bytesRead) / Double(total)))
            }
        }
    }

    /// A password protects the file from others, and this protects the phone from the file. Whoever made it could have
    /// written any path, and nothing may land outside the side folder.
    static func destination(of name: String, in folder: URL) throws -> URL {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let isAllowed = name == databaseEntry || (parts.first == recordingsFolder && parts.count > 1)
        guard isAllowed, !name.contains("\0"), !name.hasPrefix("/"),
              !parts.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty })
        else {
            throw ArchiveError.damaged
        }
        return parts.reduce(folder) { $0.appending(path: $1) }
    }
}
