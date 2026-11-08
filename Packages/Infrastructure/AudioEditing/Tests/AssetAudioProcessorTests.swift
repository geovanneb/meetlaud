@testable import AudioEditing
@preconcurrency import AVFoundation
import Domain
import Foundation
import Testing

struct AssetAudioProcessorTests {
    private let directory: URL
    private let processor = AssetAudioProcessor()

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func tone(_ name: String, seconds: Double) throws -> URL {
        let url = directory.appending(path: name)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1))
        let frames = AVAudioFrameCount(seconds * 24000)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channel = try #require(buffer.floatChannelData?[0])
        for index in 0 ..< Int(frames) {
            channel[index] = Float(sin(Double(index) * 0.05)) * 0.3
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func seconds(of url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    @Test func `a wav imports as m4a with the same length`() async throws {
        let source = try tone("memo.wav", seconds: 2)
        let output = directory.appending(path: "out.m4a")
        let duration = try await processor.importAudio(from: source, to: output)
        #expect(abs(duration - 2) < 0.1)
        #expect(try await abs(seconds(of: output) - 2) < 0.2)
    }

    /// Real AAC at a low sample rate, like files from other apps. Generated WAV hid a failure here.
    @Test func `a real m4a imports`() async throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = repo.appending(path: "App/Resources/speed-test.m4a")
        let data = try Data(contentsOf: source)
        let copy = directory.appending(path: "clip.m4a")
        try data.write(to: copy)
        let output = directory.appending(path: "out.m4a")
        let duration = try await processor.importAudio(from: copy, to: output)
        #expect(abs(duration - 30) < 0.5)
    }

    @Test func `merging joins the lengths and keeps the originals`() async throws {
        let first = try tone("a.wav", seconds: 1)
        let second = try tone("b.wav", seconds: 2)
        let output = directory.appending(path: "merged.m4a")
        let duration = try await processor.merge([first, second], to: output)
        #expect(abs(duration - 3) < 0.1)
        #expect(try await abs(seconds(of: output) - 3) < 0.2)
        #expect(FileManager.default.fileExists(atPath: first.path))
    }

    @Test func `a remote URL is refused`() async throws {
        let source = try #require(URL(string: "https://example.com/audio.mp3"))
        await #expect(throws: AudioEditingError.self) {
            try await processor.importAudio(from: source, to: directory.appending(path: "out.m4a"))
        }
    }

    @Test func `a file with no audio is refused and leaves nothing`() async throws {
        let source = directory.appending(path: "notes.m4a")
        try Data("not audio".utf8).write(to: source)
        let output = directory.appending(path: "out.m4a")
        await #expect(throws: (any Error).self) {
            try await processor.importAudio(from: source, to: output)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}

struct SpeechWindowReaderTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Tone with silence at `quietAt`, so that the place to cut is obvious.
    private func speechLike(seconds: Double, quietAt: Double? = nil) throws -> URL {
        let url = directory.appending(path: "audio.wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let frames = AVAudioFrameCount(seconds * 16000)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channel = try #require(buffer.floatChannelData?[0])
        for index in 0 ..< Int(frames) {
            let time = Double(index) / 16000
            let isQuiet = quietAt.map { abs(time - $0) < 0.2 } ?? false
            channel[index] = isQuiet ? 0 : Float(sin(Double(index) * 0.1)) * 0.5
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func read(_ reader: SpeechWindowReader, _ url: URL, from start: TimeInterval = 0) async throws
        -> [AudioWindow]
    {
        var windows: [AudioWindow] = []
        for try await window in reader.windows(of: url, from: start) {
            windows.append(window)
        }
        return windows
    }

    @Test func `windows cover the whole file with no gaps`() async throws {
        let url = try speechLike(seconds: 25)
        let windows = try await read(SpeechWindowReader(windowDuration: 10, searchDuration: 2), url)
        #expect(windows.count == 3)
        #expect(windows.first?.start == 0)
        for (previous, next) in zip(windows, windows.dropFirst()) {
            #expect(previous.end == next.start)
        }
        #expect(abs((windows.last?.end ?? 0) - 25) < 0.1)
    }

    @Test func `a window ends at the silence, not in the middle of a word`() async throws {
        let url = try speechLike(seconds: 25, quietAt: 8.5)
        let windows = try await read(SpeechWindowReader(windowDuration: 10, searchDuration: 3), url)
        #expect(abs((windows.first?.end ?? 0) - 8.5) < 0.25)
    }

    @Test func `reading can start from a checkpoint`() async throws {
        let url = try speechLike(seconds: 20)
        let windows = try await read(SpeechWindowReader(windowDuration: 10, searchDuration: 2), url, from: 15)
        #expect(windows.first?.start == 15)
        #expect(abs((windows.last?.end ?? 0) - 20) < 0.1)
    }

    @Test func `no window is larger than the limit, so memory stays flat`() async throws {
        let url = try speechLike(seconds: 30)
        let windows = try await read(SpeechWindowReader(windowDuration: 10, searchDuration: 2), url)
        #expect(windows.allSatisfy { $0.samples.count <= 160_000 })
    }
}
