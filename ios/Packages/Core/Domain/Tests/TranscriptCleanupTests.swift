@testable import Domain
import Foundation
import Testing

struct TranscriptCleanupTests {
    @Test func `a model stuck in a loop keeps one copy and says how many were left out`() {
        let looped = Array(repeating: "thank you", count: 8).joined(separator: ", ")
        #expect(TranscriptCleanup.markRepeats("So, \(looped)") == "So, thank you [×8]")
    }

    @Test func `a few repeats are how people talk, and stay`() {
        let text = "no, no, no, no, I said no"
        #expect(TranscriptCleanup.markRepeats(text) == text)
    }

    @Test func `numbers are never folded`() {
        let digits = Array(repeating: "10", count: 8).joined(separator: " ")
        #expect(TranscriptCleanup.markRepeats(digits) == digits)
    }

    @Test func `a word is never cut in half`() {
        let text = "banananananananana split"
        #expect(TranscriptCleanup.markRepeats(text) == text)
    }

    @Test func `scripts without spaces fold too`() {
        let looped = String(repeating: "ありがとう。", count: 7)
        #expect(TranscriptCleanup.markRepeats(looped) == "ありがとう [×7]")
    }

    @Test(arguments: [
        ("no", "nobody"), ("sim", "simples"), ("sí", "síntesis"),
    ])
    func `a repeated prefix never consumes the next word`(word: String, next: String) {
        let text = Array(repeating: word, count: 5).joined(separator: " ") + " " + next
        #expect(TranscriptCleanup.markRepeats(text) == text)
    }

    @Test func `a real loop ends before a word with the same prefix`() {
        let text = Array(repeating: "no", count: 7).joined(separator: " ") + " nobody agreed"
        #expect(TranscriptCleanup.markRepeats(text) == "no [×7] nobody agreed")
    }

    @Test func `the silence annotation is not meeting text`() {
        #expect(!TranscriptCleanup.hasWords("  [BLANK_AUDIO]\n"))
        #expect(TranscriptCleanup.hasWords("The annotation says [BLANK_AUDIO]."))
    }

    @Test func `punctuation alone is no speech`() {
        #expect(!TranscriptCleanup.hasWords(" , . … "))
        #expect(TranscriptCleanup.hasWords("ok"))
        #expect(TranscriptCleanup.hasWords("42"))
        #expect(TranscriptCleanup.hasWords("はい"))
    }
}

struct JobProgressTests {
    private let start = Date(timeIntervalSince1970: 1000)

    @Test func `time left comes from the speed of this run`() {
        let progress = JobProgress(
            phase: .transcribing, fraction: 0.5, phaseStartedAt: start, phaseStartFraction: 0.25,
        )
        // A quarter took 60 seconds, so the half that is left takes 120.
        #expect(progress.estimatedRemaining(at: start.addingTimeInterval(60)) == 120)
    }

    @Test func `no promise until there is enough to measure`() {
        let early = JobProgress(phase: .transcribing, fraction: 0.02, phaseStartedAt: start, phaseStartFraction: 0)
        #expect(early.estimatedRemaining(at: start.addingTimeInterval(30)) == nil)
        let preparing = JobProgress(phase: .preparing, fraction: 0.5, phaseStartedAt: start)
        #expect(preparing.estimatedRemaining(at: start.addingTimeInterval(30)) == nil)
    }

    @Test func `only transcribing has a fraction worth a bar`() {
        #expect(JobProgress(phase: .transcribing, fraction: 0.3).isMeasurable)
        #expect(!JobProgress(phase: .preparing, fraction: 0).isMeasurable)
        #expect(!JobProgress(phase: .separatingSpeakers, fraction: 1).isMeasurable)
    }
}
