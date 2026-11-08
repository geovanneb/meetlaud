import Domain
import Foundation

public actor FakeDiarizationEngine: DiarizationEngine {
    public var turns: [SpeakerTurn]
    public var error: (any Error)?
    public private(set) var unloads = 0

    public init(turns: [SpeakerTurn] = []) {
        self.turns = turns
    }

    public func setError(_ error: (any Error)?) {
        self.error = error
    }

    public func prepare(model _: ModelDescriptor, folder _: URL?) async throws {}

    public func diarize(file _: URL) async throws -> [SpeakerTurn] {
        if let error {
            throw error
        }
        return turns
    }

    public func unload() {
        unloads += 1
    }
}

public actor FakeSpeakerStore: SpeakerStore {
    public private(set) var all: [Speaker] = []
    public private(set) var assignments: [UUID: UUID] = [:]
    public private(set) var everyone: [Person] = []
    public private(set) var prints: [VoicePrint] = []

    public init() {}

    public func speakers(for id: RecordingID) -> [Speaker] {
        all.filter { $0.recordingID == id }.sorted { $0.number < $1.number }
    }

    public func saveSpeakers(_ speakers: [Speaker], assignments: [UUID: UUID], for id: RecordingID) {
        all.removeAll { $0.recordingID == id }
        all.append(contentsOf: speakers)
        self.assignments.merge(assignments) { $1 }
    }

    public func update(_ speaker: Speaker) {
        if let index = all.firstIndex(where: { $0.id == speaker.id }) {
            all[index] = speaker
        }
    }

    public func setSpeaker(_ speakerID: UUID, forSegment segmentID: UUID) {
        assignments[segmentID] = speakerID
    }

    public func merge(_ source: UUID, into target: UUID) {
        for (segment, speaker) in assignments where speaker == source {
            assignments[segment] = target
        }
        all.removeAll { $0.id == source }
    }

    public func people() -> [Person] {
        everyone
    }

    public func insert(_ person: Person) {
        everyone.append(person)
    }

    public func update(_ person: Person) {
        if let index = everyone.firstIndex(where: { $0.id == person.id }) {
            everyone[index] = person
        }
    }

    public func delete(person id: UUID) {
        everyone.removeAll { $0.id == id }
        prints.removeAll { $0.personID == id }
    }

    public func merge(person source: UUID, into target: Person) {
        for index in all.indices where all[index].personID == source {
            all[index].personID = target.id
            all[index].name = target.name
        }
        let kept = Set(prints.filter { $0.personID == target.id }.map(\.modelID))
        prints = prints.compactMap { print in
            guard print.personID == source else { return print }
            return kept.contains(print.modelID) ? nil : VoicePrint(
                personID: target.id, modelID: print.modelID, embedding: print.embedding, talkTime: print.talkTime,
            )
        }
        everyone.removeAll { $0.id == source }
    }

    public func voicePrints(modelID: String) -> [VoicePrint] {
        prints.filter { $0.modelID == modelID }
    }

    public func save(_ print: VoicePrint) {
        prints.removeAll { $0.personID == print.personID && $0.modelID == print.modelID }
        prints.append(print)
    }

    public func recordings(with person: UUID) -> [RecordingID] {
        all.filter { $0.personID == person }.map(\.recordingID)
    }
}

/// Answers by what is being asked, like a real model would, and records every request.
public actor ScriptedLanguageEngine: LanguageModelEngine {
    public private(set) var requests: [LanguageRequest] = []
    public private(set) var prepares = 0
    public private(set) var unloads = 0
    public var failAfter: Int?
    /// What the next questions get. After these, a plain answer that cites the first line.
    public var answers: [String] = []
    /// Holds each answer until released, to test suspending in the middle of one.
    public var delay: Duration?

    public init() {}

    public func setFailAfter(_ value: Int?) {
        failAfter = value
    }

    public func setAnswers(_ value: [String]) {
        answers = value
    }

    public func setDelay(_ value: Duration?) {
        delay = value
    }

    public func prepare(model _: ModelDescriptor, folder _: URL?) async throws {
        prepares += 1
    }

    public func unload() {
        unloads += 1
    }

    private func respond(to request: LanguageRequest) throws -> String {
        if let failAfter, requests.count >= failAfter {
            throw CocoaError(.fileReadUnknown)
        }
        requests.append(request)
        if request.system.contains("You answer questions") {
            return answers.isEmpty ? "Ana opened the meeting [1]." : answers.removeFirst()
        }
        if request.system.contains("You design templates") {
            return "Name: Drafted\nInstructions: Focus.\nSection: Notes\nTask section: Next\n"
        }
        if request.system.contains("You take notes") {
            return "[1] A note from this part\n"
        }
        if request.system.contains("in three columns") {
            return "[1] Ana | Send the report | Friday\n[1] Stranger | Do something | -\n"
        }
        return "**Key points:**\n- [1] Ana opened the meeting\n- [9999] A claim about nothing\nNo citation here\n"
    }

    public nonisolated func generate(_ request: LanguageRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let delay = await self.delay {
                        try await Task.sleep(for: delay)
                    }
                    try await continuation.yield(self.respond(to: request))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public actor FakeSummaryStore: SummaryStore {
    public private(set) var all: [Summary] = []
    public private(set) var jobs: [SummaryJob] = []
    public private(set) var templates: [SummaryTemplate] = []

    public init() {}

    public func summaries(for id: RecordingID) -> [Summary] {
        all.filter { $0.recordingID == id }
    }

    public func save(_ summary: Summary) {
        all.removeAll { $0.id == summary.id }
        all.append(summary)
    }

    public func save(_ summary: Summary, job: SummaryJob) {
        save(summary)
        save(job)
    }

    public func complete(_ summary: Summary) {
        var finished = summary
        finished.isComplete = true
        save(finished)
        deleteSummaryJob(summary.id)
    }

    public func deleteSummary(_ id: UUID) {
        all.removeAll { $0.id == id }
    }

    public func summaryJobs() -> [SummaryJob] {
        jobs
    }

    public func save(_ job: SummaryJob) {
        if let index = jobs.firstIndex(where: { $0.summaryID == job.summaryID }) {
            jobs[index] = job
        } else {
            jobs.append(job)
        }
    }

    public func deleteSummaryJob(_ summaryID: UUID) {
        jobs.removeAll { $0.summaryID == summaryID }
    }

    public func userTemplates() -> [SummaryTemplate] {
        templates
    }

    public func save(_ template: SummaryTemplate) {
        templates.removeAll { $0.id == template.id }
        templates.append(template)
    }

    public func deleteTemplate(_ id: String) {
        templates.removeAll { $0.id == id }
    }
}

public actor FakeRemindersProvider: RemindersProvider {
    public private(set) var added: [String] = []

    public init() {}

    public func add(title: String, notes _: String?) {
        added.append(title)
    }
}
