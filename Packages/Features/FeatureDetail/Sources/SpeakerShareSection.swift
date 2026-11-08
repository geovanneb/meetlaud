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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isChoosingCount = false
    @State private var hasSpeakerModel = false

    private var stats: [SpeakerStat] {
        SpeakerStats.compute(speakers: model.speakers, segments: model.segments)
    }

    var body: some View {
        let stats = stats
        Group {
            // Voices being separated again, on a transcript that is already there.
            if model.isRedetectingSpeakers {
                HStack(spacing: Spacing.compact) {
                    ProgressRing(fraction: nil)
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(L10n.Transcript.stepSpeakers)
                            .font(.dsHeading)
                            .foregroundStyle(Color.dsPrimaryText)
                        Text(L10n.Transcript.speakersNote)
                            .font(.dsMeta)
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                }
                .dsCard()
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
                .riseTransition()
            } else if stats.count > 1 {
                // One voice has nothing to compare, and the line would only say "100%". It still offers to look
                // again: a phone on a table can hear four people and report one (SP-3).
                shares(stats)
            } else if canRedetect {
                oneVoice
            }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.bottom, Spacing.small)
        .sheet(item: $selected) { speaker in
            SpeakerSheet(speaker: speaker, model: model)
        }
        .confirmationDialog(
            L10n.Detail.speakersCountTitle,
            isPresented: $isChoosingCount,
            titleVisibility: .visible,
        ) {
            Button(L10n.Detail.speakersCountAuto) { redetect(.automatic) }
            ForEach(SpeakerCount.choices, id: \.self) { count in
                Button(L10n.Detail.speakersCountPeople(count)) { redetect(.exactly(count)) }
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.Detail.speakersRedetectNote)
        }
        .task(id: model.segments.count) {
            hasSpeakerModel = await model.canSeparateSpeakers()
        }
    }

    /// Only for a finished transcript, with a speaker model, and when nothing is running on this meeting.
    private var canRedetect: Bool {
        hasSpeakerModel && model.transcript?.isComplete == true && !model.segments.isEmpty && model.progress == nil
    }

    private func shares(_ stats: [SpeakerStat]) -> some View {
        DisclosureGroup(isExpanded: $isExpanded.animation(reduceMotion ? Motion.reduced : Motion.standard)) {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                ForEach(stats) { stat in
                    if let speaker = model.speakers.first(where: { $0.id == stat.speakerID }) {
                        row(stat, speaker: speaker)
                    }
                }
                if canRedetect {
                    redetectButton
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
        .dsCard()
        .accessibilityIdentifier("summary.speakers")
    }

    private var oneVoice: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.compact) {
                oneVoiceText
                Spacer(minLength: Spacing.small)
                redetectButton
            }
            VStack(alignment: .leading, spacing: Spacing.compact) {
                oneVoiceText
                redetectButton
            }
        }
        .dsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("summary.speakersOne")
    }

    private var oneVoiceText: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Label(L10n.Detail.speakersOne, systemImage: "person.wave.2")
                .font(.dsHeading)
                .foregroundStyle(Color.dsPrimaryText)
            Text(L10n.Detail.speakersWrong)
                .font(.dsMeta)
                .foregroundStyle(Color.dsSecondaryText)
        }
    }

    private var redetectButton: some View {
        Button(L10n.Detail.speakersRedetect, systemImage: "arrow.triangle.2.circlepath") {
            isChoosingCount = true
        }
        .secondaryAction(.regular)
        .accessibilityIdentifier("summary.speakersRedetect")
    }

    private func redetect(_ count: SpeakerCount) {
        Task { await model.redetectSpeakers(count) }
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
