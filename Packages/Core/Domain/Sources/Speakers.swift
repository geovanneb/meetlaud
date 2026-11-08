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

/// How many voices a recording holds, when the person knows it.
public enum SpeakerCount: Hashable, Sendable {
    /// The model decides. Right most of the time, but a short recording from a phone on a table can merge
    /// everyone into one voice.
    case automatic
    /// The person said how many people spoke.
    case exactly(Int)

    /// The counts a person can pick. One voice needs no separating, and more than this is rare in a meeting.
    public static let choices = Array(2 ... 10)
}

public protocol DiarizationEngine: ModelRunner {
    /// Reads the file by streaming, so that memory stays flat however long the meeting is.
    func diarize(file: URL, speakers: SpeakerCount) async throws -> [SpeakerTurn]
}

public extension DiarizationEngine {
    func diarize(file: URL) async throws -> [SpeakerTurn] {
        try await diarize(file: file, speakers: .automatic)
    }
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

    public func run(id: RecordingID, file: URL, speakers count: SpeakerCount = .automatic) async throws {
        guard let resolved = await model() else { return }
        try await engine.prepare(model: resolved.model, folder: resolved.folder)
        let raw: [SpeakerTurn]
        do {
            raw = try await engine.diarize(file: file, speakers: count)
        } catch {
            await engine.unload()
            throw error
        }
        await engine.unload()
        // A count the person chose is kept whole. Otherwise a "voice" heard for a moment is a cough or a click.
        let turns = count == .automatic ? Self.withoutPassingSounds(raw) : raw

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

    /// A voice heard for less than this in a whole recording does not become a speaker.
    static let leastSpeech: TimeInterval = 2

    /// Drops voices heard too little to be a person. Their moments go to whoever else was speaking then, so no
    /// phrase ends up under a speaker nobody can name.
    static func withoutPassingSounds(_ turns: [SpeakerTurn]) -> [SpeakerTurn] {
        var talk: [String: TimeInterval] = [:]
        for turn in turns {
            talk[turn.speaker, default: 0] += turn.end - turn.start
        }
        let kept = turns.filter { talk[$0.speaker, default: 0] >= leastSpeech }
        // With nothing left, the short sounds are all there is, and some speaker beats none.
        return kept.isEmpty ? turns : kept
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

    /// FluidAudio's embeddings are raw, so each turn is normalized before it counts, by its length in time.
    static func centroid(_ turns: [SpeakerTurn]) -> [Float] {
        guard let size = turns.first(where: { !$0.embedding.isEmpty })?.embedding.count else { return [] }
        var sum = [Float](repeating: 0, count: size)
        for turn in turns where turn.embedding.count == size {
            let weight = Float(turn.end - turn.start)
            let unit = VoiceMatcher.normalized(turn.embedding)
            for index in sum.indices {
                sum[index] += unit[index] * weight
            }
        }
        return VoiceMatcher.normalized(sum)
    }

    /// Each person gets one speaker at most, and each speaker one person. Every pair is scored, and the closest
    /// pairs are settled first. Asking each speaker for its single best person instead lets two speakers chase the
    /// same one, and the second goes unnamed even when its own person was a close second.
    private func recognize(_ speakers: inout [Labeled], prints: [VoicePrint]) async throws {
        guard !prints.isEmpty else { return }
        let people = try await store.people()
        let scores: [[Float]] = speakers.map { labeled in
            prints.map { VoiceMatcher.similarity(labeled.speaker.embedding, $0.embedding) }
        }
        var pairs: [Candidate] = []
        for index in speakers.indices {
            for (column, print) in prints.enumerated() where scores[index][column] >= VoiceMatcher.suggestThreshold {
                pairs.append(Candidate(index: index, person: print.personID, score: scores[index][column]))
            }
        }
        var namedSpeakers: Set<Int> = []
        var taken: Set<UUID> = []
        for pair in pairs.sorted(by: Candidate.isCloser) {
            guard !namedSpeakers.contains(pair.index), !taken.contains(pair.person) else { continue }
            // The lead is measured against people still free: someone already given to a closer voice is no rival.
            let rival = prints.indices
                .filter { prints[$0].personID != pair.person && !taken.contains(prints[$0].personID) }
                .map { scores[pair.index][$0] }
                .max() ?? -1
            guard pair.score - rival >= VoiceMatcher.minimumMargin else { continue }
            namedSpeakers.insert(pair.index)
            taken.insert(pair.person)
            speakers[pair.index].speaker.personID = pair.person
            speakers[pair.index].speaker.name = people.first { $0.id == pair.person }?.name
            speakers[pair.index].speaker.isSuggested = true
        }
    }

    private struct Candidate {
        let index: Int
        let person: UUID
        let score: Float

        /// Highest score first, then a fixed order, so that the same meeting always gets the same names.
        static func isCloser(_ lhs: Self, _ rhs: Self) -> Bool {
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.index != rhs.index {
                return lhs.index < rhs.index
            }
            return lhs.person.uuidString < rhs.person.uuidString
        }
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
