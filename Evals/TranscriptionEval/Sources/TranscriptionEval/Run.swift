import ASRWhisperKit
import AudioEditing
import Domain
import Foundation

struct Fixture: Codable {
    let id: String
    let language: String
    let audio: String
    let reference: String
    /// Vocabulary spellings, given to the engine the way the app gives them.
    var hints: [String]?
    /// The app's default: the first window finds the language, and the windows after it are told.
    var detectsLanguage: Bool?
}

struct Result: Codable {
    let id: String
    let language: String
    let reference: String
    let hypothesis: String
    let audioSeconds: Double
    let inferenceSeconds: Double
    let windows: Int
    let lastWindowEnd: Double
}

@main
struct TranscriptionEval {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4 || args.count == 5 else {
            print("Usage: TranscriptionEval <model folder> <fixtures.json> <results.json> [model id]")
            return
        }
        let manifest = URL(filePath: args[2])
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: manifest))
        let engine = WhisperKitEngine()
        let model = ModelDescriptor(
            id: args.count == 5 ? args[4] : "whisper-small", displayName: "Evaluation",
            roles: [.transcription], runtime: .whisperKit,
            languages: ["en", "ja", "pt", "es"],
        )
        try await engine.prepare(model: model, folder: URL(filePath: args[1]))
        var results: [Result] = []
        let reader = SpeechWindowReader()
        for fixture in fixtures {
            let audio = manifest.deletingLastPathComponent().appending(path: fixture.audio)
            let duration = try await reader.duration(of: audio)
            let start = Date()
            var text: [String] = []
            var windows = 0
            var lastEnd = 0.0
            var language = fixture.detectsLanguage == true ? nil : fixture.language
            for try await window in reader.windows(of: audio, from: 0) {
                let result = try await engine.transcribe(window, language: language, hints: fixture.hints ?? [])
                language = language ?? result.language
                text += result.segments.map { TranscriptCleanup.markRepeats($0.text) }
                    .filter { TranscriptCleanup.hasWords($0) }
                windows += 1
                lastEnd = window.end
            }
            results.append(Result(
                id: fixture.id, language: fixture.language, reference: fixture.reference,
                hypothesis: text.joined(separator: " "), audioSeconds: duration,
                inferenceSeconds: Date().timeIntervalSince(start), windows: windows, lastWindowEnd: lastEnd,
            ))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(results).write(to: URL(filePath: args[3]), options: .atomic)
            print("Finished \(fixture.id): \(windows) window(s), \(Int(duration)) seconds of audio")
        }
        await engine.unload()
    }
}
