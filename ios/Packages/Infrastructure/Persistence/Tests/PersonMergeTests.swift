import Domain
import Foundation
import GRDB
@testable import Persistence
import Testing

struct PersonMergeTests {
    private func print(_ person: Person, _ model: String, _ value: Float) -> VoicePrint {
        VoicePrint(personID: person.id, modelID: model, embedding: [value], talkTime: 10)
    }

    @Test func `merging moves meetings and leaves one person`() async throws {
        let store = try DatabaseStore(database: DatabaseQueue())
        let meeting = Recording(title: "Sync", createdAt: .now)
        try await store.insert(meeting)
        let duplicate = Person(name: "Ana S", createdAt: .now)
        let target = Person(name: "Ana Souza", createdAt: .now)
        try await store.insert(duplicate)
        try await store.insert(target)
        let speaker = Speaker(recordingID: meeting.id, number: 1, name: "Ana S", personID: duplicate.id)
        try await store.saveSpeakers([speaker], assignments: [:], for: meeting.id)

        try await store.merge(person: duplicate.id, into: target)

        #expect(try await store.people().map(\.id) == [target.id])
        #expect(try await store.recordings(with: target.id) == [meeting.id])
        #expect(try await store.speakers(for: meeting.id).first?.name == "Ana Souza")
    }

    @Test func `the target's voice print wins, and a print only the duplicate had survives`() async throws {
        let store = try DatabaseStore(database: DatabaseQueue())
        let duplicate = Person(name: "A", createdAt: .now)
        let target = Person(name: "B", createdAt: .now)
        try await store.insert(duplicate)
        try await store.insert(target)
        try await store.save(print(duplicate, "shared", 1))
        try await store.save(print(target, "shared", 2))
        try await store.save(print(duplicate, "only", 3))

        try await store.merge(person: duplicate.id, into: target)

        #expect(try await store.voicePrints(modelID: "shared").map(\.embedding) == [[2]])
        #expect(try await store.voicePrints(modelID: "only").map(\.personID) == [target.id])
    }
}
