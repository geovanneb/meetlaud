import Foundation

/// Whether the voices a diarizer found are clearly different people.
///
/// The automatic count can merge voices that are plainly apart: on a real 2-minute meeting, four people came out as
/// one, while asking for four gave voices with prints no closer than 0.25. So an engine can try more speakers, and
/// keep the largest count whose voices all stay far apart. Measured on real meetings (SP-3): one person split in two
/// scored 0.77 to 0.94, and different people 0.01 to 0.39, with one pair of similar voices at 0.75 to 0.78. The bar
/// sits well below the splits, so a person is never cut in two; voices that close need the person to give the count.
public enum VoiceSeparation {
    /// Voices whose prints are closer than this might be one person.
    public static let distinct: Float = 0.5
    /// The most speakers tried without being asked.
    public static let mostSpeakers = 8

    /// The similarity of the two closest voices, from each one's blended print. Nil with fewer than two voices.
    public static func closestPair(_ turns: [SpeakerTurn]) -> Float? {
        let voices = Dictionary(grouping: turns, by: \.speaker).values.map { SpeakerPipeline.centroid($0) }
        var closest: Float?
        for first in voices.indices {
            for second in voices.indices where second > first {
                let score = VoiceMatcher.similarity(voices[first], voices[second])
                closest = max(closest ?? score, score)
            }
        }
        return closest
    }

    /// Whether every pair of voices is clearly apart.
    public static func areDistinct(_ turns: [SpeakerTurn]) -> Bool {
        (closestPair(turns) ?? -1) < distinct
    }
}
