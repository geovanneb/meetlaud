import Foundation

/// Someone who spoke in one recording. `name` stays nil until a person is known, and the UI shows "Speaker N".
public struct Speaker: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let recordingID: RecordingID
    public let number: Int
    public var name: String?
    public var personID: UUID?
    /// The name came from a voice print and nobody confirmed it yet.
    public var isSuggested: Bool
    public var embedding: [Float]
    public var talkTime: TimeInterval

    public init(
        id: UUID = UUID(),
        recordingID: RecordingID,
        number: Int,
        name: String? = nil,
        personID: UUID? = nil,
        isSuggested: Bool = false,
        embedding: [Float] = [],
        talkTime: TimeInterval = 0,
    ) {
        self.id = id
        self.recordingID = recordingID
        self.number = number
        self.name = name
        self.personID = personID
        self.isSuggested = isSuggested
        self.embedding = embedding
        self.talkTime = talkTime
    }
}

public struct Person: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

/// A vector that describes a voice. It is not audio, and audio cannot be rebuilt from it.
/// Vectors from different models cannot be compared, so each one records its model.
public struct VoicePrint: Hashable, Sendable {
    public let personID: UUID
    public let modelID: String
    public var embedding: [Float]
    public var talkTime: TimeInterval

    public init(personID: UUID, modelID: String, embedding: [Float], talkTime: TimeInterval) {
        self.personID = personID
        self.modelID = modelID
        self.embedding = embedding
        self.talkTime = talkTime
    }
}

/// One stretch of one voice, from the diarization model.
public struct SpeakerTurn: Hashable, Sendable {
    public let speaker: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let embedding: [Float]

    public init(speaker: String, start: TimeInterval, end: TimeInterval, embedding: [Float]) {
        self.speaker = speaker
        self.start = start
        self.end = end
        self.embedding = embedding
    }
}

/// Anything that loads a heavy model.
public protocol ModelRunner: Sendable {
    /// Loads the model. The first time, Core ML compiles it, which can take a while.
    func prepare(model: ModelDescriptor, folder: URL?) async throws
    /// Frees the memory.
    func unload() async
}

public protocol DiarizationEngine: ModelRunner {
    /// Reads the file by streaming, so that memory stays flat however long the meeting is.
    func diarize(file: URL) async throws -> [SpeakerTurn]
}

public protocol SpeakerStore: Sendable {
    func speakers(for id: RecordingID) async throws -> [Speaker]
    /// Replaces the recording's speakers and assigns each phrase in one transaction.
    func saveSpeakers(_ speakers: [Speaker], assignments: [UUID: UUID], for id: RecordingID) async throws
    func update(_ speaker: Speaker) async throws
    func setSpeaker(_ speakerID: UUID, forSegment segmentID: UUID) async throws
    /// Moves every phrase from one speaker to another, and removes the first.
    func merge(_ source: UUID, into target: UUID) async throws

    func people() async throws -> [Person]
    func insert(_ person: Person) async throws
    func update(_ person: Person) async throws
    /// Removes the person and their voice prints. Names in old transcripts stay.
    func delete(person id: UUID) async throws
    /// One transaction. Their meetings follow, and the target's voice print wins where both have one.
    func merge(person source: UUID, into target: Person) async throws
    func voicePrints(modelID: String) async throws -> [VoicePrint]
    func save(_ print: VoicePrint) async throws
    func recordings(with person: UUID) async throws -> [RecordingID]
}

public enum VoiceMatch: Equatable, Sendable {
    /// Close enough to show the name as a suggestion.
    case suggested(personID: UUID, score: Float)
    /// Too close to ignore, too far to name. Keeps "Speaker N".
    case uncertain(personID: UUID, score: Float)
    case unknown
}

/// Compares voices. A wrong name in a meeting record is worse than no name, so the thresholds lean careful.
public enum VoiceMatcher {
    /// Provisional until SP-3 measures them on real voices.
    public static let suggestThreshold: Float = 0.75
    public static let uncertainThreshold: Float = 0.6

    public static func similarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot: Float = 0
        var left: Float = 0
        var right: Float = 0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            left += lhs[index] * lhs[index]
            right += rhs[index] * rhs[index]
        }
        let scale = (left * right).squareRoot()
        return scale > 0 ? dot / scale : 0
    }

    public static func match(_ embedding: [Float], against prints: [VoicePrint]) -> VoiceMatch {
        let scored = prints.map { ($0.personID, similarity(embedding, $0.embedding)) }
        guard let best = scored.max(by: { $0.1 < $1.1 }) else { return .unknown }
        if best.1 >= suggestThreshold {
            return .suggested(personID: best.0, score: best.1)
        }
        if best.1 >= uncertainThreshold {
            return .uncertain(personID: best.0, score: best.1)
        }
        return .unknown
    }

    /// The average of two embeddings, weighted by how much speech each one saw.
    public static func blend(
        _ lhs: [Float],
        weight leftWeight: TimeInterval,
        _ rhs: [Float],
        weight rightWeight: TimeInterval,
    ) -> [Float] {
        guard lhs.count == rhs.count, leftWeight + rightWeight > 0 else { return rhs }
        let left = Float(leftWeight / (leftWeight + rightWeight))
        return zip(lhs, rhs).map { $0 * left + $1 * (1 - left) }
    }
}

/// Turns raw turns into the recording's speakers, and recognizes people who were saved before.
public struct SpeakerPipeline: Sendable {
    public typealias ModelResolver = @Sendable () async -> (model: ModelDescriptor, folder: URL?)?

    private let store: any SpeakerStore
    private let transcripts: any TranscriptStore
    private let engine: any DiarizationEngine
    private let model: ModelResolver

    public init(
        store: any SpeakerStore,
        transcripts: any TranscriptStore,
        engine: any DiarizationEngine,
        model: @escaping ModelResolver,
    ) {
        self.store = store
        self.transcripts = transcripts
        self.engine = engine
        self.model = model
    }

    /// Whether there is anything to run. With no model, transcripts simply have no speakers.
    public func isAvailable() async -> Bool {
        await model() != nil
    }

    public func run(id: RecordingID, file: URL) async throws {
        guard let resolved = await model() else { return }
        try await engine.prepare(model: resolved.model, folder: resolved.folder)
        let turns: [SpeakerTurn]
        do {
            turns = try await engine.diarize(file: file)
        } catch {
            await engine.unload()
            throw error
        }
        await engine.unload()

        let segments = try await transcripts.segments(for: id)
        let assignment = SpeakerAlignment.assign(segments: segments, turns: turns)
        var speakers = Self.speakers(from: turns, id: id)
        let prints = try await store.voicePrints(modelID: resolved.model.id)
        try await recognize(&speakers, prints: prints)

        let byLabel = Dictionary(uniqueKeysWithValues: speakers.map { ($0.label, $0.speaker) })
        var assignments: [UUID: UUID] = [:]
        for (segmentID, label) in assignment {
            assignments[segmentID] = byLabel[label]?.id
        }
        try await store.saveSpeakers(speakers.map(\.speaker), assignments: assignments, for: id)
    }

    private typealias Labeled = (label: String, speaker: Speaker)

    /// Numbered by who spoke first, which is how people read a transcript.
    private static func speakers(from turns: [SpeakerTurn], id: RecordingID) -> [Labeled] {
        var order: [String] = []
        for turn in turns.sorted(by: { $0.start < $1.start }) where !order.contains(turn.speaker) {
            order.append(turn.speaker)
        }
        return order.enumerated().map { index, label in
            let own = turns.filter { $0.speaker == label }
            let talk = own.reduce(0) { $0 + ($1.end - $1.start) }
            return (label, Speaker(
                recordingID: id,
                number: index + 1,
                embedding: centroid(own),
                talkTime: talk,
            ))
        }
    }

    private static func centroid(_ turns: [SpeakerTurn]) -> [Float] {
        guard let size = turns.first(where: { !$0.embedding.isEmpty })?.embedding.count else { return [] }
        var sum = [Float](repeating: 0, count: size)
        for turn in turns where turn.embedding.count == size {
            let weight = Float(turn.end - turn.start)
            for index in sum.indices {
                sum[index] += turn.embedding[index] * weight
            }
        }
        return sum
    }

    /// Each person gets one speaker at most: the closest match wins.
    private func recognize(_ speakers: inout [Labeled], prints: [VoicePrint]) async throws {
        let people = try await store.people()
        var taken: Set<UUID> = []
        let ranked = speakers.indices.compactMap { index -> Candidate? in
            guard case let .suggested(person, score) = VoiceMatcher.match(
                speakers[index].speaker.embedding, against: prints,
            ) else { return nil }
            return Candidate(index: index, person: person, score: score)
        }
        for match in ranked.sorted(by: { $0.score > $1.score }) where !taken.contains(match.person) {
            taken.insert(match.person)
            speakers[match.index].speaker.personID = match.person
            speakers[match.index].speaker.name = people.first { $0.id == match.person }?.name
            speakers[match.index].speaker.isSuggested = true
        }
    }

    private struct Candidate {
        let index: Int
        let person: UUID
        let score: Float
    }
}

public enum SpeakerError: Error, Equatable {
    case tooLittleSpeech
    case noEmbedding
}

/// What a person can do with speakers and saved voices.
public struct SpeakerService: Sendable {
    /// Below this, a voice print would be unreliable.
    public static let minimumTalkTime: TimeInterval = 10

    private let store: any SpeakerStore
    private let modelID: @Sendable () async -> String?
    private let now: @Sendable () -> Date

    public init(
        store: any SpeakerStore,
        modelID: @escaping @Sendable () async -> String?,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.store = store
        self.modelID = modelID
        self.now = now
    }

    public func rename(_ speaker: Speaker, to name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var speaker = speaker
        speaker.name = trimmed.isEmpty ? nil : trimmed
        speaker.personID = nil
        speaker.isSuggested = false
        try await store.update(speaker)
    }

    public func assign(_ speaker: Speaker, to person: Person) async throws {
        var speaker = speaker
        speaker.name = person.name
        speaker.personID = person.id
        speaker.isSuggested = false
        try await store.update(speaker)
    }

    public func setSpeaker(_ speaker: Speaker, forSegment id: UUID) async throws {
        try await store.setSpeaker(speaker.id, forSegment: id)
    }

    public func merge(_ source: Speaker, into target: Speaker) async throws {
        try await store.merge(source.id, into: target.id)
    }

    /// Accepting a suggestion also teaches the voice print, so recognition gets better with use.
    public func confirm(_ speaker: Speaker) async throws {
        guard let personID = speaker.personID else { return }
        var speaker = speaker
        speaker.isSuggested = false
        try await store.update(speaker)
        try await learn(speaker, personID: personID)
    }

    /// Creates a person from this speaker's voice. The caller must already have the user's consent.
    @discardableResult
    public func saveVoicePrint(of speaker: Speaker, name: String) async throws -> Person {
        guard speaker.talkTime >= Self.minimumTalkTime else { throw SpeakerError.tooLittleSpeech }
        guard !speaker.embedding.isEmpty, let modelID = await modelID() else { throw SpeakerError.noEmbedding }
        let person = Person(name: name.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: now())
        try await store.insert(person)
        try await store.save(VoicePrint(
            personID: person.id, modelID: modelID, embedding: speaker.embedding, talkTime: speaker.talkTime,
        ))
        try await assign(speaker, to: person)
        return person
    }

    public func rename(_ person: Person, to name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var person = person
        person.name = trimmed
        try await store.update(person)
    }

    public func delete(_ person: Person) async throws {
        try await store.delete(person: person.id)
    }

    /// For the same person saved twice. Their meetings keep working, under the name that stays.
    public func merge(_ source: Person, into target: Person) async throws {
        guard source.id != target.id else { return }
        try await store.merge(person: source.id, into: target)
    }

    public func recordings(with person: Person) async throws -> [RecordingID] {
        try await store.recordings(with: person.id)
    }

    private func learn(_ speaker: Speaker, personID: UUID) async throws {
        guard let modelID = await modelID(), !speaker.embedding.isEmpty else { return }
        let existing = try await store.voicePrints(modelID: modelID).first { $0.personID == personID }
        guard let existing else { return }
        try await store.save(VoicePrint(
            personID: personID,
            modelID: modelID,
            embedding: VoiceMatcher.blend(
                existing.embedding, weight: existing.talkTime,
                speaker.embedding, weight: speaker.talkTime,
            ),
            talkTime: existing.talkTime + speaker.talkTime,
        ))
    }
}
