@preconcurrency import AVFAudio
import Domain
import Foundation

/// Converts microphone buffers and writes them. Runs on the audio tap's thread, behind a lock.
final class CapturePipeline: @unchecked Sendable {
    private let lock = NSLock()
    private let target = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: SegmentFormat.sampleRate,
        channels: 1,
        interleaved: true,
    )
    private var writer: PCMSegmentWriter?
    private var converter: AVAudioConverter?
    private var isPaused = false
    private var hasFailed = false
    private let onEvent: @Sendable (CaptureEvent) -> Void

    init(onEvent: @escaping @Sendable (CaptureEvent) -> Void) {
        self.onEvent = onEvent
    }

    func begin(directory: URL) {
        lock.withLock {
            writer = PCMSegmentWriter(directory: directory)
            isPaused = false
            hasFailed = false
        }
    }

    /// Call whenever the input format may have changed. The output format never changes.
    func prepare(inputFormat: AVAudioFormat) {
        lock.withLock {
            converter = target.flatMap { AVAudioConverter(from: inputFormat, to: $0) }
        }
    }

    func setPaused(_ paused: Bool) {
        lock.withLock { isPaused = paused }
    }

    func finish() throws {
        try lock.withLock {
            try writer?.close()
            writer = nil
            converter = nil
        }
    }

    func process(_ input: AVAudioPCMBuffer) {
        lock.withLock {
            guard !isPaused, !hasFailed, let writer, let converter, let target else { return }
            let level = Self.level(of: input)
            do {
                guard let output = Self.convert(input, with: converter, to: target) else { return }
                let samples = UnsafeBufferPointer(
                    start: output.int16ChannelData?[0],
                    count: Int(output.frameLength),
                )
                try writer.append(samples)
                onEvent(.progress(
                    recorded: Double(writer.framesWritten) / SegmentFormat.sampleRate,
                    level: level,
                ))
            } catch {
                // Usually a full disk. Stop writing and report, instead of failing again on every buffer.
                hasFailed = true
                onEvent(.failed(error.localizedDescription))
            }
        }
    }

    private static func convert(
        _ input: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to format: AVAudioFormat,
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) var consumed = false
        nonisolated(unsafe) let source = input
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return source
        }
        return status == .error ? nil : output
    }

    /// Perceptual level from 0 to 1, for the waveform.
    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0 ..< Int(buffer.frameLength) {
            sum += channel[index] * channel[index]
        }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        return min(max((decibels + 55) / 55, 0), 1)
    }
}
