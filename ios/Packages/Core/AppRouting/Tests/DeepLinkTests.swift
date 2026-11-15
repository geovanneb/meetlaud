@testable import AppRouting
import Domain
import Foundation
import Testing

struct DeepLinkTests {
    private let id = "123E4567-E89B-12D3-A456-426614174000"

    private func route(_ string: String) throws -> AppRoute? {
        try DeepLink.route(from: #require(URL(string: string)))
    }

    @Test func `parses record`() throws {
        #expect(try route("meetlaud://record") == .record)
    }

    @Test func `parses recording with and without time`() throws {
        let recordingID = try #require(RecordingID(string: id))
        #expect(try route("meetlaud://recording/\(id)") == .recording(recordingID, at: nil))
        #expect(try route("meetlaud://recording/\(id)?t=125.4") == .recording(recordingID, at: 125.4))
    }

    @Test func `parses ask`() throws {
        let recordingID = try #require(RecordingID(string: id))
        #expect(try route("meetlaud://ask") == .ask(recording: nil))
        #expect(try route("meetlaud://ask?recording=\(id)") == .ask(recording: recordingID))
    }

    @Test func `parses model settings`() throws {
        #expect(try route("meetlaud://settings/models") == .modelSettings)
    }

    @Test(arguments: [
        "https://record",
        "meetlaud://",
        "meetlaud://unknown",
        "meetlaud://record/start",
        "meetlaud://recording",
        "meetlaud://recording/not-a-uuid",
        "meetlaud://recording/123E4567-E89B-12D3-A456-426614174000?t=-1",
        "meetlaud://recording/123E4567-E89B-12D3-A456-426614174000?t=nan",
        "meetlaud://recording/123E4567-E89B-12D3-A456-426614174000?t=inf",
        "meetlaud://ask?recording=bad",
        "meetlaud://settings/unknown",
    ])
    func `rejects invalid URLs`(_ url: String) throws {
        #expect(try route(url) == nil)
    }
}
