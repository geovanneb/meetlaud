import Foundation

/// How much one speaker took part in a meeting.
public struct SpeakerStat: Identifiable, Hashable, Sendable {
    public var id: UUID {
        speakerID
    }

    public let speakerID: UUID
    /// The length of the phrases given to this speaker.
    public let talkTime: TimeInterval
    /// Of the speech given to anyone, from 0 to 1. Silence and phrases with no speaker do not count.
    public let share: Double
    /// Times this speaker took the floor: phrases in a row by the same voice count once.
    public let turns: Int
    public let longestTurn: TimeInterval

    public init(speakerID: UUID, talkTime: TimeInterval, share: Double, turns: Int, longestTurn: TimeInterval) {
        self.speakerID = speakerID
        self.talkTime = talkTime
        self.share = share
        self.turns = turns
        self.longestTurn = longestTurn
    }
}

public enum SpeakerStats {
    /// Read from the transcript, not from the diarization model, so that merging speakers or moving a phrase to
    /// someone else changes the numbers too. Most speech first. Speakers with no phrases are left out.
    public static func compute(speakers: [Speaker], segments: [TranscriptSegment]) -> [SpeakerStat] {
        let known = Set(speakers.map(\.id.uuidString))
        var talk: [String: TimeInterval] = [:]
        var turns: [String: Int] = [:]
        var longest: [String: TimeInterval] = [:]

        var current: Turn?
        func closeTurn() {
            guard let turn = current else { return }
            turns[turn.speaker, default: 0] += 1
            longest[turn.speaker] = max(longest[turn.speaker] ?? 0, turn.end - turn.start)
            current = nil
        }

        for segment in segments.sorted(by: { $0.start < $1.start }) {
            guard let speaker = segment.speaker, known.contains(speaker) else {
                // A phrase nobody said still breaks a turn: whoever speaks next takes the floor again.
                closeTurn()
                continue
            }
            talk[speaker, default: 0] += max(0, segment.end - segment.start)
            if let turn = current, turn.speaker == speaker {
                current = Turn(speaker: speaker, start: turn.start, end: max(turn.end, segment.end))
            } else {
                closeTurn()
                current = Turn(speaker: speaker, start: segment.start, end: segment.end)
            }
        }
        closeTurn()

        let total = talk.values.reduce(0, +)
        guard total > 0 else { return [] }
        return speakers
            .compactMap { speaker -> (Int, SpeakerStat)? in
                let key = speaker.id.uuidString
                guard let time = talk[key], time > 0 else { return nil }
                return (speaker.number, SpeakerStat(
                    speakerID: speaker.id,
                    talkTime: time,
                    share: time / total,
                    turns: turns[key] ?? 0,
                    longestTurn: longest[key] ?? 0,
                ))
            }
            .sorted { $0.1.talkTime != $1.1.talkTime ? $0.1.talkTime > $1.1.talkTime : $0.0 < $1.0 }
            .map(\.1)
    }

    private struct Turn {
        let speaker: String
        let start: TimeInterval
        let end: TimeInterval
    }
}
