@testable import AudioCapture
@preconcurrency import AVFAudio
import Foundation
import Testing

struct SegmentTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func write(seconds: Double, to writer: PCMSegmentWriter) throws {
        let frames = Int(seconds * SegmentFormat.sampleRate)
        let samples = (0 ..< frames).map { Int16(sin(Double($0) * 0.05) * 8000) }
        try samples.withUnsafeBufferPointer { try writer.append($0) }
    }

    private func parts() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    @Test func `audio rolls over into numbered segments`() throws {
        let writer = PCMSegmentWriter(directory: directory, segmentDuration: 1)
        try write(seconds: 2.5, to: writer)
        try writer.close()
        #expect(try parts() == ["part-000001.pcm", "part-000002.pcm", "part-000003.pcm"])
        #expect(writer.framesWritten == 60000)
    }

    @Test func `assembling produces audio of the same length`() async throws {
        let writer = PCMSegmentWriter(directory: directory, segmentDuration: 1)
        try write(seconds: 2.5, to: writer)
        try writer.close()

        let output = directory.appending(path: "final.m4a")
        let duration = try await AACAssembler().assemble(segments: directory, into: output)

        #expect(abs(duration - 2.5) < 0.001)
        let file = try AVAudioFile(forReading: output)
        #expect(abs(Double(file.length) / file.processingFormat.sampleRate - 2.5) < 0.2)
    }

    /// The reason this format exists. No close, no flush: this is what a crash leaves behind.
    @Test func `audio from an abandoned writer is fully recoverable`() async throws {
        do {
            let writer = PCMSegmentWriter(directory: directory, segmentDuration: 1)
            try write(seconds: 1.5, to: writer)
        }
        let output = directory.appending(path: "final.m4a")
        let duration = try await AACAssembler().assemble(segments: directory, into: output)
        #expect(abs(duration - 1.5) < 0.001)
    }

    @Test func `half a sample at the end of a file is tolerated`() async throws {
        let writer = PCMSegmentWriter(directory: directory, segmentDuration: 10)
        try write(seconds: 1, to: writer)
        try writer.close()
        let handle = try FileHandle(forWritingTo: directory.appending(path: "part-000001.pcm"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0x01]))
        try handle.close()

        let output = directory.appending(path: "final.m4a")
        let duration = try await AACAssembler().assemble(segments: directory, into: output)
        #expect(abs(duration - 1) < 0.001)
    }

    @Test func `segments survive assembly`() async throws {
        let writer = PCMSegmentWriter(directory: directory, segmentDuration: 10)
        try write(seconds: 1, to: writer)
        try writer.close()
        _ = try await AACAssembler().assemble(segments: directory, into: directory.appending(path: "final.m4a"))
        #expect(try parts().contains("part-000001.pcm"))
    }

    @Test func `no audio is an error, and leaves no file`() async throws {
        let output = directory.appending(path: "final.m4a")
        await #expect(throws: AssemblyError.self) {
            try await AACAssembler().assemble(segments: directory, into: output)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}
