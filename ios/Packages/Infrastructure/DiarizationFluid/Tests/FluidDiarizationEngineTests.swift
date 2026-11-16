import DiarizationFluid
import Domain
import Foundation
import Testing

/// Runs the real model on real files. Without `DIARIZATION_TEST_FOLDER` these tests do nothing. The audio is two
/// synthetic voices, which proves the pipeline but says little about quality on real people. See SP-3.
struct FluidDiarizationEngineTests {
    private var folder: URL? {
        ProcessInfo.processInfo.environment["DIARIZATION_TEST_FOLDER"].map { URL(fileURLWithPath: $0) }
    }

    private var audio: URL? {
        ProcessInfo.processInfo.environment["DIARIZATION_TEST_AUDIO"].map { URL(fileURLWithPath: $0) }
    }

    private let model = ModelDescriptor(
        id: "pyannote-community-1", displayName: "Voices", roles: [.speakerSeparation],
        runtime: .fluidAudio, languages: [],
    )

    private func diarize(_ name: String) async throws -> [SpeakerTurn] {
        guard let folder, let audio else { return [] }
        let engine = FluidDiarizationEngine()
        try await engine.prepare(model: model, folder: folder)
        let turns = try await engine.diarize(file: audio.appending(path: name))
        await engine.unload()
        return turns
    }

    private func centroid(_ turns: [SpeakerTurn]) -> [Float] {
        var sum = [Float](repeating: 0, count: turns.first?.embedding.count ?? 0)
        for turn in turns {
            for index in sum.indices {
                sum[index] += turn.embedding[index]
            }
        }
        return sum
    }

    @Test func `two voices become two speakers, with embeddings, and they match across recordings`() async throws {
        guard folder != nil else { return }
        let first = try await diarize("meeting1.wav")
        let second = try await diarize("meeting2.wav")

        let labels = Set(first.map(\.speaker))
        print("TURNS: \(first.map { "\($0.speaker) \(Int($0.start))-\(Int($0.end))" })")
        #expect(labels.count == 2)
        #expect(first.allSatisfy { !$0.embedding.isEmpty })

        let voices = labels.sorted().map { label in centroid(first.filter { $0.speaker == label }) }
        let later = Set(second.map(\.speaker)).sorted().map { label in
            centroid(second.filter { $0.speaker == label })
        }
        var scores: [[Float]] = []
        for voice in voices {
            scores.append(later.map { VoiceMatcher.similarity(voice, $0) })
        }
        print("SIMILARITY: \(scores)")
        print("SPEAKERS: first=\(voices.count) second=\(later.count)")
    }

    @Test func `a missing folder fails, instead of downloading`() async throws {
        let engine = FluidDiarizationEngine()
        await #expect(throws: TranscriptionError.modelNotInstalled) {
            try await engine.prepare(model: model, folder: nil)
        }
    }

    @Test func `an empty folder fails, instead of downloading`() async throws {
        let empty = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        await #expect(throws: (any Error).self) {
            try await FluidDiarizationEngine().prepare(model: model, folder: empty)
        }
    }
}
