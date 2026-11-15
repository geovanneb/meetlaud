import Foundation

/// The on-disk format of audio while it is being recorded.
///
/// Raw samples, with no header and no container. A test with SIGKILL showed that AAC in CAF or M4A loses its audio
/// when a process dies mid-write, because the metadata is finalized on close. Raw data has nothing to corrupt: the
/// file size is the length. See docs/research/SP-4-capture-resilience.md.
public enum SegmentFormat {
    public static let sampleRate = 24000.0
    public static let bytesPerFrame = 2
    public static let fileExtension = "pcm"
}

/// Appends 16-bit mono samples to numbered files. Not thread-safe: the caller serializes access.
public final class PCMSegmentWriter {
    private let directory: URL
    private let framesPerSegment: Int64
    private let framesPerSync: Int64

    private var handle: FileHandle?
    private var segmentIndex = 0
    private var framesInSegment: Int64 = 0
    private var framesSinceSync: Int64 = 0
    public private(set) var framesWritten: Int64 = 0

    /// - Parameters:
    ///   - segmentDuration: Short files limit how much one bad write can touch.
    ///   - syncInterval: Upper limit of audio lost on power failure. A process crash loses nothing.
    public init(directory: URL, segmentDuration: TimeInterval = 60, syncInterval: TimeInterval = 5) {
        self.directory = directory
        framesPerSegment = Int64(segmentDuration * SegmentFormat.sampleRate)
        framesPerSync = Int64(syncInterval * SegmentFormat.sampleRate)
    }

    public func append(_ samples: UnsafeBufferPointer<Int16>) throws {
        guard !samples.isEmpty else { return }
        var remaining = samples[...]
        while !remaining.isEmpty {
            if handle == nil || framesInSegment >= framesPerSegment {
                try rollOver()
            }
            let count = min(remaining.count, Int(framesPerSegment - framesInSegment))
            let chunk = UnsafeBufferPointer(rebasing: remaining.prefix(count))
            try handle?.write(contentsOf: UnsafeRawBufferPointer(chunk))
            framesInSegment += Int64(count)
            framesSinceSync += Int64(count)
            framesWritten += Int64(count)
            remaining = remaining.dropFirst(count)
        }
        if framesSinceSync >= framesPerSync {
            try handle?.synchronize()
            framesSinceSync = 0
        }
    }

    public func close() throws {
        try handle?.synchronize()
        try handle?.close()
        handle = nil
    }

    private func rollOver() throws {
        try close()
        segmentIndex += 1
        framesInSegment = 0
        let url = directory.appending(path: Self.name(for: segmentIndex))
        guard FileManager.default.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
    }

    static func name(for index: Int) -> String {
        "part-\(String(format: "%06d", index)).\(SegmentFormat.fileExtension)"
    }
}
