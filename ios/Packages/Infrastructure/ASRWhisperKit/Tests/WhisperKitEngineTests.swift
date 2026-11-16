@testable import ASRWhisperKit
import AudioEditing
import Domain
import Foundation
import Testing

/// Runs the real model, so it needs the files on disk. Without `WHISPER_TEST_FOLDER` these tests do nothing.
struct WhisperKitEngineTests {
    private var folder: URL? {
        ProcessInfo.processInfo.environment["WHISPER_TEST_FOLDER"].map { URL(fileURLWithPath: $0) }
    }

    private var clip: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "App/Resources/speed-test.m4a")
    }

    private let model = ModelDescriptor(
        id: "whisper-small", displayName: "Small", roles: [.transcription], runtime: .whisperKit, languages: ["en"],
    )

    private func samples() async throws -> [Float] {
        var iterator = SpeechWindowReader().windows(of: clip, from: 0).makeAsyncIterator()
        return try #require(try await iterator.next()).samples
    }

    private func window(_ samples: [Float]) -> AudioWindow {
        AudioWindow(start: 0, end: Double(samples.count) / 16000, samples: samples)
    }

    @Test func `only audio with no signal counts as silent`() {
        #expect(WhisperKitEngine.isSilent([Float](repeating: 0, count: 16000)))
        #expect(WhisperKitEngine.isSilent([0.0004, -0.0009, 0]))
        // A very quiet voice or a quiet room is still audio for the model to judge.
        #expect(!WhisperKitEngine.isSilent([0, 0.002, 0]))
        #expect(!WhisperKitEngine.isSilent([0, -0.3, 0]))
    }

    @Test func `hints never empty the transcript`() async throws {
        guard let folder else { return }
        let engine = WhisperKitEngine()
        try await engine.prepare(model: model, folder: folder)
        let audio = try await samples()
        let plain = try await engine.transcribe(window(audio), language: "en")
        let hinted = try await engine.transcribe(window(audio), language: "en", hints: ["Garden Project", "Marlow"])
        #expect(!plain.segments.isEmpty)
        #expect(!hinted.segments.isEmpty)
        await engine.unload()
    }

    @Test func `silence gives no text`() async throws {
        guard let folder else { return }
        let engine = WhisperKitEngine()
        try await engine.prepare(model: model, folder: folder)
        let result = try await engine.transcribe(window([Float](repeating: 0, count: 160_000)), language: "en")
        #expect(result.segments.isEmpty)
        await engine.unload()
    }

    @Test(arguments: [30.0, 30.02, 31, 35, 62, 180])
    func `any window length transcribes`(seconds: Double) async throws {
        guard let folder else { return }
        let engine = WhisperKitEngine()
        try await engine.prepare(model: model, folder: folder)
        let base = try await samples()
        let count = Int(seconds * 16000)
        let audio = (0 ..< count).map { base[$0 % base.count] }
        let result = try await engine.transcribe(window(audio), language: "en")
        #expect(!result.segments.isEmpty)
        await engine.unload()
    }

    @Test func `the engine refuses a folder with no tokenizer`() async throws {
        let empty = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        await #expect(throws: TranscriptionError.missingModelFiles) {
            try await WhisperKitEngine().prepare(model: model, folder: empty)
        }
    }
}
