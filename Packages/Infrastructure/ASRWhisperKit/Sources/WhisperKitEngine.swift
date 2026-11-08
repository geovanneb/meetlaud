import Domain
import Foundation
@preconcurrency import WhisperKit

/// Runs Whisper on the Neural Engine, from files already on the device.
public actor WhisperKitEngine: TranscriptionEngine {
    private var whisper: WhisperKit?
    private var loadedModelID: String?

    public init() {}

    public func prepare(model: ModelDescriptor, folder: URL?) async throws {
        guard loadedModelID != model.id else { return }
        guard let folder else { throw TranscriptionError.modelNotInstalled }
        // Without a local tokenizer, WhisperKit silently downloads one. That would break the app's main promise,
        // from inside a dependency that no check can see, so a missing file stops here.
        let modelFolder = folder.appending(path: "model")
        for file in ["tokenizer.json", "tokenizer_config.json"] {
            guard FileManager.default.fileExists(atPath: folder.appending(path: file).path) else {
                throw TranscriptionError.missingModelFiles
            }
        }
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            tokenizerFolder: folder,
            computeOptions: ModelComputeOptions(
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine,
            ),
            verbose: false,
            logLevel: .none,
            prewarm: true,
            load: true,
            download: false,
        )
        whisper = try await WhisperKit(config)
        loadedModelID = model.id
    }

    public func transcribe(_ window: AudioWindow, language: String?, hints: [String]) async throws -> WindowResult {
        guard let whisper else { throw TranscriptionError.modelNotInstalled }
        // Whisper reads a prompt only with the prefill, which needs a language. With "detect", the first window
        // finds it, and every window after that gets the hints.
        let prompt = language == nil ? nil : Self.promptTokens(hints, tokenizer: whisper.tokenizer)
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            usePrefillPrompt: language != nil,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            wordTimestamps: false,
            promptTokens: prompt,
            // Pieces run side by side. Two keeps memory and heat close to one piece at a time, which this app must
            // hold for hours; the default of four is meant for short clips.
            concurrentWorkerCount: 2,
            // Cuts each window at its pauses into pieces of up to 30 seconds, the length Whisper was trained on.
            // One long piece makes it seek through silence, which is where it invents text and repeats itself.
            chunkingStrategy: .vad,
        )
        let results = try await whisper.transcribe(audioArray: window.samples, decodeOptions: options)
        let segments = results.flatMap(\.segments).map { segment in
            SpeechSegment(start: Double(segment.start), end: Double(segment.end), text: segment.text)
        }
        return WindowResult(segments: segments, language: results.first?.language)
    }

    /// The terms as a comma-separated list, the way Whisper was shown spellings in training.
    private static func promptTokens(_ hints: [String], tokenizer: (any WhisperTokenizer)?) -> [Int]? {
        guard !hints.isEmpty, let tokenizer else { return nil }
        let tokens = tokenizer.encode(text: " " + hints.joined(separator: ", "))
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return tokens.isEmpty ? nil : tokens
    }

    public func unload() async {
        await whisper?.unloadModels()
        whisper = nil
        loadedModelID = nil
    }
}
