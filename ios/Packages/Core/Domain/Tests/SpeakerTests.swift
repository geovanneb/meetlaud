@testable import Domain
import Foundation
import Testing
import TestSupport

private struct Boom: Error {}

private let model = ModelDescriptor(
    id: "voices", displayName: "Voices", roles: [.speakerSeparation, .voicePrint],
    runtime: .fluidAudio, languages: [],
)

private func segment(_ id: RecordingID, _ start: Double, _ end: Double) -> TranscriptSegment {
    TranscriptSegment(recordingID: id, start: start, end: end, text: "Text")
}

private func turn(_ speaker: String, _ start: Double, _ end: Double, _ voice: [Float] = [1, 0]) -> SpeakerTurn {
    SpeakerTurn(speaker: speaker, start: start, end: end, embedding: voice)
}

struct SpeakerAlignmentTests {
    private let id = RecordingID()

    @Test func `a phrase goes to whoever overlaps it the most`() {
        let phrase = segment(id, 10, 20)
        let result = SpeakerAlignment.assign(
            segments: [phrase],
            turns: [turn("A", 8, 12), turn("B", 12, 20)],
        )
        #expect(result[phrase.id] == "B")
    }

    @Test func `several short turns add up`() {
        let phrase = segment(id, 0, 10)
        let result = SpeakerAlignment.assign(
            segments: [phrase],
            turns: [turn("A", 0, 3), turn("B", 3, 6), turn("A", 6, 8)],
        )
        #expect(result[phrase.id] == "A")
    }

    @Test func `a phrase with no speech stays unassigned`() {
        let phrase = segment(id, 50, 60)
        #expect(SpeakerAlignment.assign(segments: [phrase], turns: [turn("A", 0, 10)]).isEmpty)
    }

    @Test func `ties are decided the same way every time`() {
        let phrase = segment(id, 0, 10)
        let turns = [turn("B", 0, 5), turn("A", 5, 10)]
        #expect(SpeakerAlignment.assign(segments: [phrase], turns: turns)[phrase.id] == "A")
        #expect(SpeakerAlignment.assign(segments: [phrase], turns: turns.reversed())[phrase.id] == "A")
    }
}

struct VoiceMatcherTests {
    private let person = UUID()

    private func prints(_ voice: [Float]) -> [VoicePrint] {
        [VoicePrint(personID: person, modelID: "m", embedding: voice, talkTime: 60)]
    }

    @Test func `identical voices score one, and opposite ones minus one`() {
        #expect(abs(VoiceMatcher.similarity([1, 2], [2, 4]) - 1) < 0.0001)
        #expect(abs(VoiceMatcher.similarity([1, 0], [-1, 0]) + 1) < 0.0001)
    }

    @Test func `mismatched or empty vectors never match`() {
        #expect(VoiceMatcher.similarity([1], [1, 2]) == 0)
        #expect(VoiceMatcher.similarity([], []) == 0)
        #expect(VoiceMatcher.similarity([0, 0], [1, 1]) == 0)
    }

    @Test func `a close voice is suggested`() {
        guard case .suggested = VoiceMatcher.match([1, 0.1], against: prints([1, 0])) else {
            Issue.record("Expected a suggestion")
            return
        }
    }

    @Test func `a middling voice is not named`() {
        guard case .uncertain = VoiceMatcher.match([1, 1.5], against: prints([1, 0])) else {
            Issue.record("Expected uncertainty")
            return
        }
    }

    @Test func `a different voice is unknown`() {
        #expect(VoiceMatcher.match([0, 1], against: prints([1, 0])) == .unknown)
    }

    @Test func `no saved voices means unknown`() {
        #expect(VoiceMatcher.match([1, 0], against: []) == .unknown)
    }

    @Test func `two saved people almost equally close leave the voice unnamed`() {
        let ana = VoicePrint(personID: UUID(), modelID: "m", embedding: [1, 0.1], talkTime: 60)
        let bia = VoicePrint(personID: UUID(), modelID: "m", embedding: [1, -0.1], talkTime: 60)
        guard case .uncertain = VoiceMatcher.match([1, 0], against: [ana, bia]) else {
            Issue.record("Expected uncertainty")
            return
        }
    }

    @Test func `blending weighs by speech time, not by vector length`() {
        let blended = VoiceMatcher.blend([100, 0], weight: 30, [0, 1], weight: 10)
        #expect(abs(blended[0] / blended[1] - 3) < 0.0001)
        #expect(abs(VoiceMatcher.similarity(blended, VoiceMatcher.normalized(blended)) - 1) < 0.0001)
    }
}

private struct PipelineHarness {
    let store = FakeSpeakerStore()
    let transcripts = FakeTranscriptStore()
    let engine: FakeDiarizationEngine
    let pipeline: SpeakerPipeline
    let id = RecordingID()
    private let file = URL(fileURLWithPath: "/tmp/a.m4a")

    init(turns: [SpeakerTurn], hasModel: Bool = true) {
        engine = FakeDiarizationEngine(turns: turns)
        pipeline = SpeakerPipeline(
            store: store, transcripts: transcripts, engine: engine,
            model: { hasModel ? (model, nil) : nil },
        )
    }

    func run(_ phrases: [TranscriptSegment]) async throws {
        try await transcripts.append(
            phrases, job: TranscriptionJob(recordingID: id, modelID: "m", language: nil),
        )
        try await pipeline.run(id: id, file: file)
    }
}

struct SpeakerPipelineTests {
    @Test func `speakers are numbered by who spoke first`() async throws {
        let harness = PipelineHarness(turns: [turn("S2", 0, 30, [1, 0]), turn("S1", 30, 60, [0, 1])])
        try await harness.run([segment(harness.id, 0, 10), segment(harness.id, 40, 50)])
        let speakers = await harness.store.speakers(for: harness.id)
        #expect(speakers.map(\.number) == [1, 2])
        #expect(speakers.first?.talkTime == 30)
    }

    @Test func `a voice heard for a moment does not become a speaker`() async throws {
        let harness = PipelineHarness(turns: [turn("A", 0, 30), turn("B", 30, 31), turn("A", 31, 60)])
        try await harness.run([segment(harness.id, 0, 10), segment(harness.id, 29, 32)])
        let speakers = await harness.store.speakers(for: harness.id)
        #expect(speakers.count == 1)
        #expect(await harness.store.assignments.count == 2, "The short sound's phrase goes to the voice around it")
    }

    @Test func `a count the person chose reaches the engine and keeps every voice`() async throws {
        let harness = PipelineHarness(turns: [turn("A", 0, 30), turn("B", 30, 31, [0, 1])])
        try await harness.transcripts.append(
            [segment(harness.id, 0, 10)], job: TranscriptionJob(recordingID: harness.id, modelID: "m", language: nil),
        )
        try await harness.pipeline.run(id: harness.id, file: URL(fileURLWithPath: "/tmp/a.m4a"), speakers: .exactly(2))
        #expect(await harness.engine.requested == [.exactly(2)])
        #expect(await harness.store.speakers(for: harness.id).count == 2)
    }

    @Test func `the engine is released afterwards`() async throws {
        let harness = PipelineHarness(turns: [turn("A", 0, 5)])
        try await harness.run([segment(harness.id, 0, 5)])
        #expect(await harness.engine.unloads == 1)
    }

    @Test func `a saved voice is recognized, and only suggested`() async throws {
        let harness = PipelineHarness(turns: [turn("A", 0, 30, [1, 0]), turn("B", 30, 60, [0, 1])])
        let ana = Person(name: "Ana", createdAt: .now)
        await harness.store.insert(ana)
        await harness.store.save(VoicePrint(personID: ana.id, modelID: "voices", embedding: [1, 0], talkTime: 60))

        try await harness.run([segment(harness.id, 0, 10), segment(harness.id, 40, 50)])

        let speakers = await harness.store.speakers(for: harness.id)
        #expect(speakers[0].name == "Ana")
        #expect(speakers[0].isSuggested)
        #expect(speakers[1].name == nil)
    }

    @Test func `one person is never given to two speakers`() async throws {
        let harness = PipelineHarness(turns: [turn("A", 0, 30, [1, 0]), turn("B", 30, 60, [1, 0.05])])
        let ana = Person(name: "Ana", createdAt: .now)
        await harness.store.insert(ana)
        await harness.store.save(VoicePrint(personID: ana.id, modelID: "voices", embedding: [1, 0], talkTime: 60))

        try await harness.run([segment(harness.id, 0, 10)])

        let named = await harness.store.speakers(for: harness.id).filter { $0.personID != nil }
        #expect(named.count == 1)
    }

    @Test func `a voice that is close to two people goes to the one still free`() async throws {
        // B is a little closer to Geovanne, but A is Geovanne beyond doubt, so B is Karen.
        let harness = PipelineHarness(turns: [turn("A", 0, 30, [1, 0]), turn("B", 30, 60, [0.8, 0.6])])
        let geovanne = Person(name: "Geovanne", createdAt: .now)
        let karen = Person(name: "Karen", createdAt: .now)
        await harness.store.insert(geovanne)
        await harness.store.insert(karen)
        await harness.store.save(VoicePrint(personID: geovanne.id, modelID: "voices", embedding: [1, 0], talkTime: 60))
        await harness.store.save(VoicePrint(
            personID: karen.id, modelID: "voices", embedding: [0.1316, 0.9913], talkTime: 60,
        ))

        try await harness.run([segment(harness.id, 0, 10), segment(harness.id, 40, 50)])

        let speakers = await harness.store.speakers(for: harness.id)
        #expect(speakers.map(\.name) == ["Geovanne", "Karen"])
    }

    @Test func `a loud stretch does not outweigh the rest of a voice`() {
        let centroid = SpeakerPipeline.centroid([turn("A", 0, 1, [100, 0]), turn("A", 1, 4, [0, 1])])
        #expect(VoiceMatcher.similarity(centroid, [0, 1]) > VoiceMatcher.similarity(centroid, [1, 0]))
    }

    @Test func `voice prints from another model are ignored`() async throws {
        let harness = PipelineHarness(turns: [turn("A", 0, 30, [1, 0])])
        let ana = Person(name: "Ana", createdAt: .now)
        await harness.store.insert(ana)
        await harness.store.save(VoicePrint(personID: ana.id, modelID: "old", embedding: [1, 0], talkTime: 60))

        try await harness.run([segment(harness.id, 0, 10)])

        #expect(await harness.store.speakers(for: harness.id).first?.name == nil)
    }

    @Test func `with no model, nothing happens`() async {
        let harness = PipelineHarness(turns: [], hasModel: false)
        #expect(await harness.pipeline.isAvailable() == false)
    }
}

private struct ServiceHarness {
    let store = FakeSpeakerStore()
    let service: SpeakerService

    init(hasModel: Bool = true) {
        let store = store
        service = SpeakerService(store: store, modelID: { hasModel ? "voices" : nil })
    }

    func speaker(talkTime: TimeInterval = 60, embedding: [Float] = [1, 0]) async -> Speaker {
        let speaker = Speaker(recordingID: RecordingID(), number: 1, embedding: embedding, talkTime: talkTime)
        await store.saveSpeakers([speaker], assignments: [:], for: speaker.recordingID)
        return speaker
    }
}

struct SpeakerServiceTests {
    @Test func `saving a voice stores a vector and names the speaker`() async throws {
        let harness = ServiceHarness()
        let speaker = await harness.speaker()
        let person = try await harness.service.saveVoicePrint(of: speaker, name: " Ana ")
        #expect(person.name == "Ana")
        #expect(await harness.store.prints.first?.embedding == [1, 0])
        #expect(await harness.store.all.first?.name == "Ana")
    }

    @Test func `too little speech cannot become a voice print`() async throws {
        let harness = ServiceHarness()
        let speaker = await harness.speaker(talkTime: 3)
        await #expect(throws: SpeakerError.tooLittleSpeech) {
            try await harness.service.saveVoicePrint(of: speaker, name: "Ana")
        }
        #expect(await harness.store.everyone.isEmpty)
    }

    @Test func `confirming a suggestion teaches the voice print`() async throws {
        let harness = ServiceHarness()
        let ana = Person(name: "Ana", createdAt: .now)
        await harness.store.insert(ana)
        await harness.store.save(VoicePrint(personID: ana.id, modelID: "voices", embedding: [0, 0], talkTime: 30))
        var speaker = await harness.speaker(talkTime: 10, embedding: [4, 4])
        speaker.personID = ana.id
        speaker.isSuggested = true

        try await harness.service.confirm(speaker)

        let print = await harness.store.prints.first
        #expect(abs(VoiceMatcher.similarity(print?.embedding ?? [], [1, 1]) - 1) < 0.0001)
        #expect(print?.talkTime == 40)
    }

    @Test func `renaming by hand clears the link to a saved person`() async throws {
        let harness = ServiceHarness()
        var speaker = await harness.speaker()
        speaker.personID = UUID()
        speaker.isSuggested = true
        try await harness.service.rename(speaker, to: "Bruno")
        let saved = await harness.store.all.first
        #expect(saved?.name == "Bruno")
        #expect(saved?.personID == nil)
        #expect(saved?.isSuggested == false)
    }

    @Test func `a blank name goes back to the number`() async throws {
        let harness = ServiceHarness()
        let speaker = await harness.speaker()
        try await harness.service.rename(speaker, to: "   ")
        #expect(await harness.store.all.first?.name == nil)
    }

    @Test func `deleting a person removes their voice print`() async throws {
        let harness = ServiceHarness()
        let speaker = await harness.speaker()
        let person = try await harness.service.saveVoicePrint(of: speaker, name: "Ana")
        try await harness.service.delete(person)
        #expect(await harness.store.prints.isEmpty)
        #expect(await harness.store.everyone.isEmpty)
    }
}

struct VoiceSeparationTests {
    @Test func `voices far apart are distinct people`() {
        let turns = [turn("A", 0, 10, [1, 0]), turn("B", 10, 20, [0, 1]), turn("C", 20, 30, [-1, 0.1])]
        #expect(VoiceSeparation.areDistinct(turns))
    }

    @Test func `two close voices might be one person`() {
        let turns = [turn("A", 0, 10, [1, 0]), turn("B", 10, 20, [0.9, 0.3]), turn("C", 20, 30, [0, 1])]
        #expect(!VoiceSeparation.areDistinct(turns))
    }

    @Test func `one voice has no pair to compare`() {
        #expect(VoiceSeparation.closestPair([turn("A", 0, 10)]) == nil)
    }
}
