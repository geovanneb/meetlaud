import DesignSystem
import Domain
import Localization
import SwiftUI

/// Who spoke and how much, at the top of the summary. Closed, it is one line, so the summary stays the first thing
/// read. Open, each person gets a row with their share, time, and turns. A row opens the same sheet as the
/// transcript's name chips, so a wrong name is fixed where it is noticed.
struct SpeakerShareSection: View {
    let model: DetailModel
    @AppStorage("summary.speakersExpanded") private var isExpanded = false
    @State private var selected: Speaker?

    private var stats: [SpeakerStat] {
        SpeakerStats.compute(speakers: model.speakers, segments: model.segments)
    }

    var body: some View {
        let stats = stats
        // One voice has nothing to compare, and the line would only say "100%".
        if stats.count > 1 {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    ForEach(stats) { stat in
                        if let speaker = model.speakers.first(where: { $0.id == stat.speakerID }) {
                            row(stat, speaker: speaker)
                        }
                    }
                }
                .padding(.top, Spacing.small)
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text(L10n.Detail.speakers)
                        .font(.dsHeading)
                        .foregroundStyle(Color.dsPrimaryText)
                    Text(overview(stats))
                        .font(.dsMeta)
                        .foregroundStyle(Color.dsSecondaryText)
                }
            }
            .tint(Color.dsSecondaryText)
            .padding(Spacing.medium)
            .background(Color.dsSurface, in: .rect(cornerRadius: Radius.medium))
            .padding(.horizontal, Spacing.medium)
            .padding(.bottom, Spacing.small)
            .sheet(item: $selected) { speaker in
                SpeakerSheet(speaker: speaker, model: model)
            }
            .accessibilityIdentifier("summary.speakers")
        }
    }

    private func overview(_ stats: [SpeakerStat]) -> String {
        stats.compactMap { stat in
            model.speakers.first { $0.id == stat.speakerID }.map {
                "\(model.name(of: $0)) \(stat.share.formatted(.percent.precision(.fractionLength(0))))"
            }
        }
        .joined(separator: " · ")
    }

    private func row(_ stat: SpeakerStat, speaker: Speaker) -> some View {
        let share = stat.share.formatted(.percent.precision(.fractionLength(0)))
        let label = [model.name(of: speaker), share].joined(separator: ", ")
        let detail = L10n.Detail.speakerDetail(
            time: stat.talkTime.clock, turns: stat.turns, longest: stat.longestTurn.clock,
        )
        return Button {
            selected = speaker
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.name(of: speaker))
                        .font(.dsRowTitle)
                        .foregroundStyle(Color.dsPrimaryText)
                    if speaker.isSuggested {
                        Text(L10n.People.suggested)
                            .font(.dsBadge)
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                    Spacer(minLength: Spacing.small)
                    Text(share)
                        .font(.dsRowTitle.monospacedDigit())
                        .foregroundStyle(Color.dsPrimaryText)
                }
                ProgressView(value: stat.share)
                    .tint(Color.dsAction)
                    .accessibilityHidden(true)
                Text(detail)
                    .font(.dsNote)
                    .foregroundStyle(Color.dsSecondaryText)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(detail)
        .accessibilityHint(L10n.Transcript.edit)
    }
}
