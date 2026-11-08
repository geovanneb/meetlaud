import Foundation

/// Which speaker said each phrase: the one who overlaps it the most.
public enum SpeakerAlignment {
    public static func assign(
        segments: [TranscriptSegment],
        turns: [SpeakerTurn],
    ) -> [UUID: String] {
        var result: [UUID: String] = [:]
        for segment in segments {
            var talked: [String: TimeInterval] = [:]
            for turn in turns where turn.end > segment.start && turn.start < segment.end {
                talked[turn.speaker, default: 0] += min(turn.end, segment.end) - max(turn.start, segment.start)
            }
            result[segment.id] = talked.max { lhs, rhs in
                lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
            }?.key
        }
        return result
    }
}
