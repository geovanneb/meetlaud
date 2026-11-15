@preconcurrency import AVFoundation
import Domain
import Foundation

public enum AudioEditingError: Error {
    case notLocal
    case noAudioTrack
    case exportUnavailable
}

/// Converts and joins finished files, on the device, with the system's encoder.
public struct AssetAudioProcessor: AudioProcessor {
    public init() {}

    public func importAudio(from source: URL, to file: URL) async throws -> TimeInterval {
        // AVURLAsset can read from a server. This app only ever reads files it was handed.
        guard source.isFileURL else { throw AudioEditingError.notLocal }
        let asset = AVURLAsset(url: source)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw AudioEditingError.noAudioTrack
        }
        try await export(asset, to: file)
        return try await asset.load(.duration).seconds
    }

    public func merge(_ sources: [URL], to file: URL) async throws -> TimeInterval {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid,
        ) else { throw AudioEditingError.exportUnavailable }

        var cursor = CMTime.zero
        for source in sources {
            let asset = AVURLAsset(url: source)
            let duration = try await asset.load(.duration)
            guard let audio = try await asset.loadTracks(withMediaType: .audio).first else {
                throw AudioEditingError.noAudioTrack
            }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audio, at: cursor)
            cursor = CMTimeAdd(cursor, duration)
        }
        try await export(composition, to: file)
        return cursor.seconds
    }

    private func export(_ asset: AVAsset, to file: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioEditingError.exportUnavailable
        }
        // A temporary name means that the final path only ever holds a complete file.
        let temporary = file.deletingLastPathComponent().appending(path: "\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await session.export(to: temporary, as: .m4a)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: temporary, to: file)
    }
}
