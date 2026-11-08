import Foundation

/// Cleans up a window of speech before a model hears it. The recording on disk is never changed: this runs on the
/// copy in memory that goes to transcription.
///
/// Two things, both cheap and both safe for every engine:
/// 1. A high-pass filter at 80 Hz. Speech has almost nothing there, while air conditioning, traffic, and a phone
///    knocked on a table do. Left in, that rumble takes up part of the model's range.
/// 2. Gentle leveling. A phone on a table hears the person next to it far louder than the one across the room.
///    Whisper scales each 30 seconds by its loudest moment, so the quiet voice ends up near the floor and is
///    misheard or dropped. Speech is brought toward one level, with a cap on the gain, and stretches quieter than
///    the noise floor are never raised, so that silence does not turn into hiss that the model reads as words.
///
/// Noise suppression with a neural model would help more in loud rooms, but it needs a model of its own, so it is a
/// separate decision.
public struct SpeechConditioner: Sendable {
    public let sampleRate: Double
    public let highPassCutoff: Double
    /// Speech level to aim for, as RMS in dBFS.
    public let targetLevel: Float
    /// The most a quiet voice is raised, in dB. More than this mostly raises the room.
    public let maxGain: Float
    /// Frames this far above the noise floor count as speech, in dB.
    public let speechMargin: Float

    public init(
        sampleRate: Double = 16000,
        highPassCutoff: Double = 80,
        targetLevel: Float = -23,
        maxGain: Float = 18,
        speechMargin: Float = 9,
    ) {
        self.sampleRate = sampleRate
        self.highPassCutoff = highPassCutoff
        self.targetLevel = targetLevel
        self.maxGain = maxGain
        self.speechMargin = speechMargin
    }

    public func process(_ samples: [Float]) -> [Float] {
        guard samples.count > Int(sampleRate * 0.1) else { return samples }
        return level(highPass(samples))
    }

    // MARK: - High-pass

    // The textbook names for a biquad's coefficients and history read better here than long ones.
    // swiftlint:disable identifier_name
    /// A second-order Butterworth, run once forward. A phase shift this low in frequency is not audible to a model.
    func highPass(_ samples: [Float]) -> [Float] {
        let omega = 2 * Double.pi * highPassCutoff / sampleRate
        let alpha = sin(omega) / (2 * 0.7071)
        let cosine = cos(omega)
        let a0 = 1 + alpha
        let b0 = Float((1 + cosine) / 2 / a0)
        let b1 = Float(-(1 + cosine) / a0)
        let b2 = b0
        let a1 = Float(-2 * cosine / a0)
        let a2 = Float((1 - alpha) / a0)

        var output = [Float](repeating: 0, count: samples.count)
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
        for index in samples.indices {
            let x0 = samples[index]
            let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            output[index] = y0
            x2 = x1
            x1 = x0
            y2 = y1
            y1 = y0
        }
        return output
    }

    // swiftlint:enable identifier_name

    // MARK: - Leveling

    /// 50 ms frames for measuring, a gain per frame, smoothed, then spread sample by sample.
    func level(_ samples: [Float]) -> [Float] {
        let frame = max(1, Int(sampleRate * 0.05))
        let frames = (samples.count + frame - 1) / frame
        var levels = [Float](repeating: -120, count: frames)
        for index in 0 ..< frames {
            let range = index * frame ..< min(samples.count, (index + 1) * frame)
            var energy: Float = 0
            for sample in samples[range] {
                energy += sample * sample
            }
            levels[index] = Self.decibels(energy / Float(range.count))
        }

        // The quietest tenth of the window is taken as the room.
        let floor = levels.sorted()[frames / 10]
        let gate = floor + speechMargin

        // A frame's gain looks at the speech around it (300 ms), so it follows a voice, not a syllable.
        let reach = 3
        var targets = [Float](repeating: 0, count: frames)
        for index in 0 ..< frames {
            let nearby = levels[max(0, index - reach) ... min(frames - 1, index + reach)]
            guard let loudest = nearby.max(), loudest >= gate else {
                // No speech nearby: leave the room as it is.
                targets[index] = 0
                continue
            }
            // Never cut: a loud voice is fine. Only quiet speech is raised.
            targets[index] = min(maxGain, max(0, targetLevel - loudest))
        }

        // Rises in 200 ms and falls in 50 ms, so that a loud voice right after a quiet one is not blown out.
        var gains = [Float](repeating: 0, count: frames)
        var current: Float = 0
        for index in 0 ..< frames {
            let target = targets[index]
            let rate: Float = target > current ? 0.25 : 1
            current += (target - current) * rate
            gains[index] = current
        }

        var output = samples
        for index in output.indices {
            let position = Float(index) / Float(frame) - 0.5
            let lower = max(0, min(frames - 1, Int(position.rounded(.down))))
            let upper = min(frames - 1, lower + 1)
            let blend = max(0, min(1, position - Float(lower)))
            let gain = gains[lower] + (gains[upper] - gains[lower]) * blend
            output[index] = Self.limit(output[index] * Self.linear(gain))
        }
        return output
    }

    static func decibels(_ power: Float) -> Float {
        10 * log10(max(power, 1e-12))
    }

    static func linear(_ decibels: Float) -> Float {
        pow(10, decibels / 20)
    }

    /// Soft above 0.9, so a raised peak bends instead of clipping into a click.
    static func limit(_ sample: Float) -> Float {
        let magnitude = abs(sample)
        guard magnitude > 0.9 else { return sample }
        let bent = 0.9 + 0.1 * tanh((magnitude - 0.9) / 0.1)
        return sample < 0 ? -bent : bent
    }
}
