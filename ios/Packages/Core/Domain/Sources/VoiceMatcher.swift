import Foundation

public enum VoiceMatch: Equatable, Sendable {
    /// Close enough to show the name as a suggestion.
    case suggested(personID: UUID, score: Float)
    /// Too close to ignore, too far to name. Keeps "Speaker N".
    case uncertain(personID: UUID, score: Float)
    case unknown
}

/// Compares voices. A wrong name in a meeting record is worse than no name, so a name needs both a close
/// score and a clear lead over the next person.
public enum VoiceMatcher {
    /// Provisional until SP-3 measures them on real voices. 0.75 came from synthetic voices, which score 0.97,
    /// and real voices on another day, room, and microphone stayed under it, so people were not recognized.
    public static let suggestThreshold: Float = 0.6
    public static let uncertainThreshold: Float = 0.45
    /// Two saved people this close to one voice is a coin toss, and a coin toss is not a name.
    public static let minimumMargin: Float = 0.08

    /// Unit length, so that a loud or long stretch does not outweigh the others. Zero stays zero.
    public static func normalized(_ vector: [Float]) -> [Float] {
        let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return length > 0 ? vector.map { $0 / length } : vector
    }

    public static func similarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot: Float = 0
        var left: Float = 0
        var right: Float = 0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            left += lhs[index] * lhs[index]
            right += rhs[index] * rhs[index]
        }
        let scale = (left * right).squareRoot()
        return scale > 0 ? dot / scale : 0
    }

    public static func match(_ embedding: [Float], against prints: [VoicePrint]) -> VoiceMatch {
        let scored = prints.map { ($0.personID, similarity(embedding, $0.embedding)) }
        guard let best = scored.max(by: { $0.1 < $1.1 }) else { return .unknown }
        let runnerUp = scored.filter { $0.0 != best.0 }.map(\.1).max() ?? -1
        if best.1 >= suggestThreshold, best.1 - runnerUp >= minimumMargin {
            return .suggested(personID: best.0, score: best.1)
        }
        if best.1 >= uncertainThreshold {
            return .uncertain(personID: best.0, score: best.1)
        }
        return .unknown
    }

    /// The average of two embeddings, weighted by how much speech each one saw. Both sides are normalized first:
    /// older prints were stored as raw sums, whose length grows with speech time and would count it twice.
    public static func blend(
        _ lhs: [Float],
        weight leftWeight: TimeInterval,
        _ rhs: [Float],
        weight rightWeight: TimeInterval,
    ) -> [Float] {
        guard lhs.count == rhs.count, leftWeight + rightWeight > 0 else { return rhs }
        let left = Float(leftWeight / (leftWeight + rightWeight))
        return normalized(zip(normalized(lhs), normalized(rhs)).map { $0 * left + $1 * (1 - left) })
    }
}
