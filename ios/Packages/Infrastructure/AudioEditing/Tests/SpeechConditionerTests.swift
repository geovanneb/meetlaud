@testable import AudioEditing
import Foundation
import Testing

struct SpeechConditionerTests {
    private let conditioner = SpeechConditioner()
    private let rate = 16000.0

    private func sine(_ frequency: Double, amplitude: Float, seconds: Double) -> [Float] {
        (0 ..< Int(seconds * rate)).map { Float(sin(2 * .pi * frequency * Double($0) / rate)) * amplitude }
    }

    private func rms(_ samples: ArraySlice<Float>) -> Float {
        (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }

    @Test func `rumble is cut, and the voice band passes`() {
        let rumble = conditioner.highPass(sine(30, amplitude: 0.5, seconds: 1))
        let voice = conditioner.highPass(sine(1000, amplitude: 0.5, seconds: 1))
        #expect(rms(rumble[8000...]) < 0.1)
        #expect(rms(voice[8000...]) > 0.33)
    }

    @Test func `a quiet voice is raised, within the cap`() {
        // Half a second of room, then a voice at about -40 dBFS.
        let input = [Float](repeating: 0.0001, count: Int(rate / 2)) + sine(300, amplitude: 0.014, seconds: 2)
        let output = conditioner.level(input)
        let gain = rms(output[16000...]) / rms(input[16000...])
        #expect(gain > 4)
        #expect(gain <= SpeechConditioner.linear(conditioner.maxGain) * 1.01)
    }

    @Test func `the room alone is not raised into hiss`() {
        let room = (0 ..< Int(rate * 2)).map { index in Float(sin(Double(index) * 12.9898) * 0.0005) }
        let output = conditioner.level(room)
        #expect(rms(output[...]) <= rms(room[...]) * 1.01)
    }

    @Test func `a loud voice is never cut, and never clips`() {
        let loud = sine(300, amplitude: 0.95, seconds: 1)
        let output = conditioner.process(loud)
        #expect(output.allSatisfy { abs($0) <= 1 })
        #expect(rms(output[4000...]) > rms(loud[4000...]) * 0.9)
    }

    @Test func `the length never changes, so timestamps stay right`() {
        let input = sine(300, amplitude: 0.1, seconds: 3.3)
        #expect(conditioner.process(input).count == input.count)
    }
}
