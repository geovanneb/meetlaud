import Domain
import Foundation
@preconcurrency import WhisperKit

/// Runs Whisper on the Neural Engine, from files already on the device.
public actor WhisperKitEngine: TranscriptionEngine {
    private var whisper: WhisperKit?
    private var loadedModelID: String?

    /// Pieces run side by side. Two keeps memory and heat close to one piece at a time, which this app must hold
    /// for hours; the default of four is meant for short clips.
    private static let concurrentPieces = 2

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
            // Nothing on the GPU. iOS refuses GPU work from an app in the background, and transcription goes on
            // there. WhisperKit's default puts the spectrogram on the GPU: every piece then failed as soon as the
            // person left the app, and came back as silence. The spectrogram is small, so the CPU loses little.
            computeOptions: ModelComputeOptions(
                melCompute: .cpuOnly,
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine,
                prefillCompute: .cpuOnly,
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

    public func transcribe(
        _ window: AudioWindow,
        language: String?,
        hints: [String],
        progress: @escaping @Sendable (Double) -> Void,
    ) async throws -> WindowResult {
        guard let whisper else { throw TranscriptionError.modelNotInstalled }
        let options = Self.options(language: language, hints: hints, tokenizer: whisper.tokenizer)
        let pieces = try await Self.pieces(of: window.samples, options: options)
        var results: [TranscriptionResult] = []
        var done = 0
        for batch in stride(from: 0, to: pieces.count, by: Self.concurrentPieces) {
            try Task.checkCancellation()
            let slice = Array(pieces[batch ..< min(batch + Self.concurrentPieces, pieces.count)])
            // WhisperKit's own chunking logs a failed piece and drops it, so a failure looked like silence and the
            // window was saved as done. Here a failed piece fails the window, and nothing is saved for it.
            let outcomes = await whisper.transcribeWithOptions(
                audioArrays: slice.map(\.audioSamples),
                decodeOptionsArray: Array(repeating: options, count: slice.count),
                seekOffsets: slice.map(\.seekOffsetIndex),
            )
            guard outcomes.count == slice.count else { throw TranscriptionError.engineFailed }
            for (piece, outcome) in zip(slice, outcomes) {
                let offset = Float(piece.seekOffsetIndex) / Float(WhisperKit.sampleRate)
                for result in try outcome.get() {
                    result.segments = result.segments.map {
                        TranscriptionUtilities.updateSegmentTimings(segment: $0, seekTime: offset)
                    }
                    results.append(result)
                }
            }
            done += slice.count
            progress(Double(done) / Double(pieces.count))
        }
        let segments = results.flatMap(\.segments).map { segment in
            SpeechSegment(start: Double(segment.start), end: Double(segment.end), text: segment.text)
        }
        return WindowResult(segments: segments, language: results.first?.language)
    }

    /// Cuts the window at its pauses into pieces of up to 30 seconds, the length Whisper was trained on. One long
    /// piece makes it seek through silence, which is where it invents text and repeats itself.
    private static func pieces(of samples: [Float], options: DecodingOptions) async throws -> [AudioChunk] {
        guard samples.count > Constants.defaultWindowSamples else {
            return [AudioChunk(seekOffsetIndex: 0, audioSamples: samples)]
        }
        return try await VADAudioChunker().chunkAll(
            audioArray: samples, maxChunkLength: Constants.defaultWindowSamples, decodeOptions: options,
        )
    }

    private static func options(
        language: String?,
        hints: [String],
        tokenizer: (any WhisperTokenizer)?,
    ) -> DecodingOptions {
        // Whisper reads a prompt only with the prefill, which needs a language. With "detect", the first window
        // finds it, and every window after that gets the hints.
        let prompt = language == nil ? nil : promptTokens(hints, tokenizer: tokenizer)
        return DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            usePrefillPrompt: language != nil,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            wordTimestamps: false,
            promptTokens: prompt,
            concurrentWorkerCount: concurrentPieces,
        )
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
