import Domain
import Foundation
import GRDB
@testable import Persistence
import Testing

struct SummaryPersistenceTests {
    private func setUp() async throws -> (DatabaseStore, RecordingID) {
        let store = try DatabaseStore(database: DatabaseQueue())
        let recording = Recording(title: "Sync", createdAt: .now)
        try await store.insert(recording)
        return (store, recording.id)
    }

    private func job(_ summary: Summary) -> SummaryJob {
        SummaryJob(
            summaryID: summary.id, recordingID: summary.recordingID, template: BuiltInTemplates.all[0],
            modelID: "m", language: nil,
        )
    }

    @Test func `a summary round-trips with its items`() async throws {
        let (store, id) = try await setUp()
        let item = SummaryItem(text: "Call", sourceTime: 12, owner: "Ana", due: "Friday", isDone: true)
        let summary = Summary(
            recordingID: id, templateName: "T", modelID: "m", language: "ja",
            sections: [SummarySection(title: "S", kind: .tasks, items: [item])],
            isComplete: true, createdAt: Date(timeIntervalSince1970: 1000),
        )
        try await store.save(summary)
        #expect(try await store.summaries(for: id) == [summary])
    }

    @Test func `a job survives with its checkpoint, and keeps its place in line`() async throws {
        let (store, id) = try await setUp()
        let first = Summary(recordingID: id, templateName: "1", modelID: "m", language: nil, createdAt: .now)
        let second = Summary(recordingID: id, templateName: "2", modelID: "m", language: nil, createdAt: .now)
        var firstJob = job(first)
        try await store.save(first, job: firstJob)
        try await Task.sleep(for: .milliseconds(5))
        try await store.save(second, job: job(second))

        firstJob.nextSection = 2
        firstJob.notes = ["[1] note"]
        try await store.save(first, job: firstJob)

        let jobs = try await store.summaryJobs()
        #expect(jobs.map(\.summaryID) == [first.id, second.id], "Saving progress must not move a job back")
        #expect(jobs.first == firstJob)
    }

    @Test func `completing removes the job in the same step`() async throws {
        let (store, id) = try await setUp()
        let summary = Summary(recordingID: id, templateName: "T", modelID: "m", language: nil, createdAt: .now)
        try await store.save(summary, job: job(summary))
        try await store.complete(summary)
        #expect(try await store.summaryJobs().isEmpty)
        #expect(try await store.summaries(for: id).first?.isComplete == true)
    }

    @Test func `deleting a recording removes its summaries and jobs`() async throws {
        let (store, id) = try await setUp()
        let summary = Summary(recordingID: id, templateName: "T", modelID: "m", language: nil, createdAt: .now)
        try await store.save(summary, job: job(summary))
        try await store.delete(id)
        #expect(try await store.summaries(for: id).isEmpty)
        #expect(try await store.summaryJobs().isEmpty)
    }

    @Test func `user templates round-trip, sorted by name`() async throws {
        let (store, _) = try await setUp()
        let sections = [TemplateSection(title: "S")]
        let later = SummaryTemplate(name: "Zebra", category: .call, instructions: "", sections: sections)
        let earlier = SummaryTemplate(name: "Alpha", category: .meeting, instructions: "I", sections: sections)
        try await store.save(later)
        try await store.save(earlier)
        #expect(try await store.userTemplates() == [earlier, later])
        try await store.deleteTemplate(earlier.id)
        #expect(try await store.userTemplates() == [later])
    }
}
