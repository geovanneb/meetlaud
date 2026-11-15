@preconcurrency import AVFAudio
import Domain
import Foundation

public enum AssemblyError: Error {
    case noAudio
}

/// Encodes raw segments into the final M4A. Never deletes the segments: the caller does, once the file is saved.
public struct AACAssembler: AudioAssembler {
    /// 64 kbps mono is about 29 MB per hour, and is plenty for speech.
    static let bitRate = 64000
    private static let chunkFrames = 24000

    public init() {}

    public func assemble(segments directory: URL, into file: URL) async throws -> TimeInterval {
        try await Task.detached(priority: .userInitiated) {
            try Self.encode(segments: directory, into: file)
        }.value
    }

    private static func encode(segments directory: URL, into file: URL) throws -> TimeInterval {
        let parts = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == SegmentFormat.fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: SegmentFormat.sampleRate,
            channels: 1,
            interleaved: true,
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunkFrames)) else {
            throw AssemblyError.noAudio
        }

        // A temporary name means that the final path only ever holds a complete file.
        let temporary = file.deletingLastPathComponent().appending(path: "\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temporary) }

        var frames: Int64 = 0
        do {
            let output = try AVAudioFile(
                forWriting: temporary,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: SegmentFormat.sampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: bitRate,
                ],
                commonFormat: .pcmFormatInt16,
                interleaved: true,
            )
            for part in parts {
                frames += try append(part, to: output, using: buffer)
            }
            output.close()
        }
        guard frames > 0 else { throw AssemblyError.noAudio }

        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: temporary, to: file)
        return Double(frames) / SegmentFormat.sampleRate
    }

    private static func append(
        _ part: URL,
        to output: AVAudioFile,
        using buffer: AVAudioPCMBuffer,
    ) throws -> Int64 {
        let handle = try FileHandle(forReadingFrom: part)
        defer { try? handle.close() }

        var frames: Int64 = 0
        while let data = try handle.read(upToCount: chunkFrames * SegmentFormat.bytesPerFrame), !data.isEmpty {
            // A crash can leave half a sample at the end of the file.
            let count = data.count / SegmentFormat.bytesPerFrame
            guard count > 0, let target = buffer.int16ChannelData?[0] else { break }
            data.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    memcpy(target, base, count * SegmentFormat.bytesPerFrame)
                }
            }
            buffer.frameLength = AVAudioFrameCount(count)
            try output.write(from: buffer)
            frames += Int64(count)
        }
        return frames
    }
}
