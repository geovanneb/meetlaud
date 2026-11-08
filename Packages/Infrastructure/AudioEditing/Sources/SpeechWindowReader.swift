@preconcurrency import AVFoundation
import Domain
import Foundation

/// Reads audio as windows at 16 kHz mono, so that memory stays flat. Three hours held in memory would take over
/// 1 GB and iOS would kill the app. Windows end at the quietest moment near the boundary, so as not to cut a word.
public struct SpeechWindowReader: AudioWindowSource {
    public static let sampleRate = 16000.0
    private let windowDuration: TimeInterval
    private let searchDuration: TimeInterval

    /// - Parameters:
    ///   - windowDuration: Also the most work a crash or a pause can lose.
    ///   - searchDuration: How far before the boundary to look for silence.
    public init(windowDuration: TimeInterval = 180, searchDuration: TimeInterval = 10) {
        self.windowDuration = windowDuration
        self.searchDuration = searchDuration
    }

    public func duration(of file: URL) async throws -> TimeInterval {
        let audio = try AVAudioFile(forReading: file)
        return Double(audio.length) / audio.processingFormat.sampleRate
    }

    public func windows(of file: URL, from start: TimeInterval) -> AsyncThrowingStream<AudioWindow, any Error> {
        let windowDuration = windowDuration
        let searchDuration = searchDuration
        return AsyncThrowingStream(bufferingPolicy: .bufferingOldest(1)) { continuation in
            let task = Task.detached(priority: .utility) {
                do {
                    var reader = try Reader(file: file, start: start)
                    while let window = try reader.next(window: windowDuration, search: searchDuration) {
                        try Task.checkCancellation()
                        continuation.yield(window)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct Reader {
        private let audio: AVAudioFile
        private let converter: AVAudioConverter
        private let format: AVAudioFormat
        private let inputBuffer: AVAudioPCMBuffer
        private var position: TimeInterval
        private var pending: [Float] = []
        private var isFinished = false

        init(file: URL, start: TimeInterval) throws {
            audio = try AVAudioFile(forReading: file)
            guard
                let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
                let converter = AVAudioConverter(from: audio.processingFormat, to: format),
                let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 32768)
            else { throw TranscriptionError.audioUnavailable }
            self.format = format
            self.converter = converter
            inputBuffer = buffer
            position = start
            audio.framePosition = AVAudioFramePosition(start * audio.processingFormat.sampleRate)
        }

        mutating func next(window: TimeInterval, search: TimeInterval) throws -> AudioWindow? {
            let target = Int(window * sampleRate)
            while pending.count < target, !isFinished {
                try readMore()
            }
            guard !pending.isEmpty else { return nil }

            let cut = isFinished && pending.count <= target
                ? pending.count
                : Self.quietestPoint(in: pending, before: min(target, pending.count), search: search)
            let samples = Array(pending.prefix(cut))
            pending.removeFirst(cut)
            let start = position
            position += Double(cut) / sampleRate
            return AudioWindow(start: start, end: position, samples: samples)
        }

        private mutating func readMore() throws {
            // Reading at the end of a file throws, instead of returning nothing.
            guard audio.framePosition < audio.length else {
                isFinished = true
                try convert(endOfStream: true)
                return
            }
            try audio.read(into: inputBuffer)
            try convert(endOfStream: false)
        }

        /// A resampler holds back a little audio. The end of the file must flush it, or the last words are lost.
        private mutating func convert(endOfStream: Bool) throws {
            let ratio = format.sampleRate / audio.processingFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(inputBuffer.frameCapacity) * ratio) + 4096
            guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                throw TranscriptionError.audioUnavailable
            }
            nonisolated(unsafe) var consumed = endOfStream
            nonisolated(unsafe) let source = inputBuffer
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                if consumed {
                    inputStatus.pointee = endOfStream ? .endOfStream : .noDataNow
                    return nil
                }
                consumed = true
                inputStatus.pointee = .haveData
                return source
            }
            if status == .error {
                throw error ?? TranscriptionError.audioUnavailable
            }
            if let channel = output.floatChannelData?[0] {
                pending.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            }
        }

        /// The end of the quietest 30 ms in the search range.
        static func quietestPoint(in samples: [Float], before limit: Int, search: TimeInterval) -> Int {
            let frame = Int(0.03 * sampleRate)
            let lowest = max(limit - Int(search * sampleRate), frame)
            var best = limit
            var bestEnergy = Float.greatestFiniteMagnitude
            var index = lowest
            while index + frame <= limit {
                var energy: Float = 0
                for offset in index ..< index + frame {
                    energy += samples[offset] * samples[offset]
                }
                if energy < bestEnergy {
                    bestEnergy = energy
                    best = index + frame / 2
                }
                index += frame
            }
            return best
        }
    }
}
