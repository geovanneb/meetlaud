@preconcurrency import AVFoundation
import CoreMedia
import Domain
import Foundation
@preconcurrency import Speech

private enum AppleLocale {
    static func locale(for language: String?) -> Locale {
        switch language {
        case "ja": Locale(identifier: "ja_JP")
        case "pt": Locale(identifier: "pt_BR")
        case "es": Locale(identifier: "es_ES")
        default: Locale(identifier: "en_US")
        }
    }
}

/// Runs Apple's on-device speech recognition. iOS owns the model.
public actor AppleSpeechEngine: TranscriptionEngine {
    public init() {}

    public func prepare(model _: ModelDescriptor, folder _: URL?) async throws {}

    public func unload() async {}

    public func transcribe(
        _ window: AudioWindow,
        language: String?,
        hints: [String],
        progress _: @escaping @Sendable (Double) -> Void,
    ) async throws -> WindowResult {
        let locale = AppleLocale.locale(for: language)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange],
        )
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.languageNotSupported
        }
        let buffer = try Self.buffer(from: window.samples, as: format)
        let (input, feed) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let collector = Task {
            var segments: [SpeechSegment] = []
            for try await result in transcriber.results {
                let range = result.range
                segments.append(SpeechSegment(
                    start: range.start.seconds,
                    end: range.end.seconds,
                    text: String(result.text.characters),
                ))
            }
            return segments
        }
        if !hints.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = hints
            try await analyzer.setContext(context)
        }
        try await analyzer.start(inputSequence: input)
        feed.yield(AnalyzerInput(buffer: buffer))
        feed.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let segments = try await collector.value
        return WindowResult(segments: segments, language: language)
    }

    private static func buffer(from samples: [Float], as format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard
            let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
            let source = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: AVAudioFrameCount(samples.count),
            ),
            let channel = source.floatChannelData?[0],
            let converter = AVAudioConverter(from: sourceFormat, to: format)
        else { throw TranscriptionError.audioUnavailable }
        source.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { pointer in
            if let base = pointer.baseAddress {
                channel.update(from: base, count: samples.count)
            }
        }
        let ratio = format.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(samples.count) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw TranscriptionError.audioUnavailable
        }
        nonisolated(unsafe) var consumed = false
        nonisolated(unsafe) let input = source
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return input
        }
        if status == .error {
            throw error ?? TranscriptionError.audioUnavailable
        }
        return output
    }
}

public struct AppleSpeechAssets: SystemSpeechAssets {
    public init() {}

    private func transcriber(for language: String) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: AppleLocale.locale(for: language),
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange],
        )
    }

    public func isInstalled(language: String) async -> Bool {
        await AssetInventory.status(forModules: [transcriber(for: language)]) == .installed
    }

    public func install(language: String) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber(for: language)],
        ) {
            try await request.downloadAndInstall()
        }
    }
}
