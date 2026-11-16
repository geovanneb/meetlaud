import Domain
import Foundation
import GRDB
@testable import Persistence
import Testing

struct TranscriptVersionTests {
    private func version(_ id: RecordingID, _ text: String, _ seconds: TimeInterval) -> TranscriptVersion {
        TranscriptVersion(
            recordingID: id, modelID: "m", language: "ja", savedAt: Date(timeIntervalSince1970: seconds),
            segments: [TranscriptSegment(recordingID: id, start: 1, end: 2, text: text)],
        )
    }

    @Test func `a version round-trips, in any language`() async throws {
        let store = try DatabaseStore(database: DatabaseQueue())
        let meeting = Recording(title: "Sync", createdAt: .now)
        try await store.insert(meeting)
        try await store.save(version(meeting.id, "こんにちは", 1))
        let saved = try await store.versions(for: meeting.id)
        #expect(saved.first?.segments.first?.text == "こんにちは")
        #expect(saved.first?.language == "ja")
    }

    @Test func `only the newest ones stay`() async throws {
        let store = try DatabaseStore(database: DatabaseQueue())
        let meeting = Recording(title: "Sync", createdAt: .now)
        try await store.insert(meeting)
        for index in 1 ... TranscriptVersion.limit + 2 {
            try await store.save(version(meeting.id, "v\(index)", TimeInterval(index)))
        }
        let texts = try await store.versions(for: meeting.id).compactMap(\.segments.first?.text)
        #expect(texts == ["v5", "v4", "v3"])
    }

    @Test func `erasing everything takes the versions too`() async throws {
        let store = try DatabaseStore(database: DatabaseQueue())
        let meeting = Recording(title: "Sync", createdAt: .now)
        try await store.insert(meeting)
        try await store.save(version(meeting.id, "private words", 1))
        try await store.eraseEverything()
        #expect(try await store.versions(for: meeting.id).isEmpty)
    }
}
