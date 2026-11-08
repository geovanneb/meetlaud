@testable import Domain
import Foundation
import Testing

struct SpeakerStatsTests {
    private let id = RecordingID()

    private func speaker(_ number: Int) -> Speaker {
        Speaker(recordingID: id, number: number)
    }

    private func phrase(_ start: Double, _ end: Double, _ speaker: Speaker?) -> TranscriptSegment {
        TranscriptSegment(recordingID: id, start: start, end: end, text: "Text", speaker: speaker?.id.uuidString)
    }

    @Test func `shares add up to one, and the most talkative comes first`() {
        let ana = speaker(1)
        let bia = speaker(2)
        let stats = SpeakerStats.compute(
            speakers: [ana, bia],
            segments: [phrase(0, 10, ana), phrase(10, 40, bia)],
        )
        #expect(stats.map(\.speakerID) == [bia.id, ana.id])
        #expect(stats.map(\.share) == [0.75, 0.25])
        #expect(stats.map(\.talkTime) == [30, 10])
    }

    @Test func `phrases in a row by the same voice are one turn`() {
        let ana = speaker(1)
        let bia = speaker(2)
        let stats = SpeakerStats.compute(
            speakers: [ana, bia],
            segments: [phrase(0, 5, ana), phrase(5, 12, ana), phrase(12, 14, bia), phrase(14, 16, ana)],
        )
        let byID = Dictionary(uniqueKeysWithValues: stats.map { ($0.speakerID, $0) })
        #expect(byID[ana.id]?.turns == 2)
        #expect(byID[ana.id]?.longestTurn == 12)
        #expect(byID[bia.id]?.turns == 1)
    }

    @Test func `a phrase with no speaker counts for nobody but ends the turn`() {
        let ana = speaker(1)
        let stats = SpeakerStats.compute(
            speakers: [ana],
            segments: [phrase(0, 5, ana), phrase(5, 20, nil), phrase(20, 25, ana)],
        )
        #expect(stats.first?.talkTime == 10)
        #expect(stats.first?.share == 1)
        #expect(stats.first?.turns == 2)
    }

    @Test func `speakers with no phrases are left out, and no speech means no stats`() {
        let ana = speaker(1)
        let bia = speaker(2)
        #expect(SpeakerStats.compute(speakers: [ana, bia], segments: [phrase(0, 5, ana)]).count == 1)
        #expect(SpeakerStats.compute(speakers: [ana], segments: []).isEmpty)
    }
}
