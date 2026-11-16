@testable import Domain
import Foundation
import Testing

struct RecordingTests {
    @Test func `duration is never negative`() {
        let recording = Recording(title: "Sync", createdAt: .now, duration: -5)
        #expect(recording.duration == 0)
    }

    @Test func `id parses a valid uuid`() throws {
        let uuid = UUID()
        let id = try #require(RecordingID(string: uuid.uuidString))
        #expect(id.rawValue == uuid)
    }

    @Test(arguments: ["", "abc", "../../etc/passwd", "123e4567-e89b-12d3-a456"])
    func `id rejects invalid input`(_ input: String) {
        #expect(RecordingID(string: input) == nil)
    }
}
