import DesignSystem
import Domain
import Localization
import SwiftUI

/// A summary as a document: every claim shows where it came from, or that it needs checking.
struct SummaryDocument: View {
    let model: DetailModel
    let summary: Summary

    var body: some View {
        let progress = model.progress(of: summary)
        LazyVStack(alignment: .leading, spacing: Spacing.compact) {
            if let progress {
                statusRow(progress)
            }
            ForEach(Array(summary.sections.enumerated()), id: \.offset) { _, section in
                Text(L10n.Summary.sectionTitle(section.title))
                    .font(.dsHeading)
                    .padding(.top, Spacing.small)
                    .accessibilityAddTraits(.isHeader)
                ForEach(section.items) { item in
                    row(item, kind: section.kind)
                }
                if section.items.isEmpty {
                    Text(L10n.Summary.emptySection)
                        .foregroundStyle(Color.dsSecondaryText)
                }
            }
            if let progress {
                partial(progress)
            } else if !summary.isComplete {
                Text(L10n.Summary.incomplete)
                    .foregroundStyle(Color.dsSecondaryText)
            }
            if summary.isComplete {
                Text(L10n.Summary.aiNote)
                    .font(.dsNote)
                    .foregroundStyle(Color.dsSecondaryText)
                    .padding(.top, Spacing.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.medium)
        .padding(.bottom, Spacing.medium)
    }

    private func statusRow(_ progress: SummaryProgress) -> some View {
        // Same vocabulary as a transcription: a waiting state is a badge, work is a bar that never stands still.
        VStack(alignment: .leading, spacing: Spacing.compact) {
            switch progress.phase {
            case .queued, .waiting:
                StatusBadge(
                    Self.status(progress), tone: progress.phase == .waiting ? .attention : .waiting,
                    symbol: progress.phase == .waiting ? "pause.circle" : "hourglass",
                )
                .accessibilityIdentifier("summary.status")
            case .reading, .writing:
                ActivityBar(fraction: progress.fraction > 0 ? progress.fraction : nil)
                Text(Self.status(progress))
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
                    .accessibilityIdentifier("summary.status")
            }
            Button(L10n.Common.cancel, role: .cancel) {
                Task { await model.cancel(summary) }
            }
            .secondaryAction(.regular)
        }
        .dsCard()
    }

    private static func status(_ progress: SummaryProgress) -> String {
        switch progress.phase {
        case .queued: L10n.Summary.statusQueued
        case .reading: L10n.Summary.statusReading
        case .writing: L10n.Summary.statusWriting
        case .waiting: L10n.Summary.statusWaiting
        }
    }

    /// Unfinished text can never be checked yet, so it stays quiet until the section is done.
    @ViewBuilder private func partial(_ progress: SummaryProgress) -> some View {
        if let text = progress.partial {
            ForEach(SummaryParser.items(from: text, kind: .bullets)) { item in
                Text(item.text.replacing("|", with: "·"))
                    .foregroundStyle(Color.dsSecondaryText)
            }
        }
    }

    private func row(_ item: SummaryItem, kind: SectionKind) -> some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            if kind == .tasks {
                checkbox(item)
            }
            itemText(item)
            if let time = item.sourceTime {
                sourceLink(time)
            }
        }
    }

    private func checkbox(_ item: SummaryItem) -> some View {
        Button {
            Task { await model.toggle(item, in: summary) }
        } label: {
            Label(
                item.isDone ? L10n.Summary.markNotDone : L10n.Summary.markDone,
                systemImage: item.isDone ? "checkmark.circle.fill" : "circle",
            )
            .labelStyle(.iconOnly)
            .foregroundStyle(item.isDone ? Color.dsAction : Color.dsSecondaryText)
            .tappableTarget()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(item.isDone ? .isSelected : [])
        .accessibilityIdentifier("summary.task")
    }

    private func itemText(_ item: SummaryItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(model.display(item.text))
                .strikethrough(item.isDone)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let detail = model.detail(of: item) {
                Text(detail)
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
            }
            if item.needsReview {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                    Image(systemName: "exclamationmark.triangle")
                        .accessibilityHidden(true)
                    Text(L10n.Summary.checkThis)
                }
                .font(.dsNote)
                .foregroundStyle(Color.dsSecondaryText)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("summary.review")
            }
        }
        // In a scroll view a row can take the height it needs, so that large text grows instead of being cut.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sourceLink(_ time: TimeInterval) -> some View {
        Button {
            model.play(from: time)
        } label: {
            Text(time.clock)
                .font(.dsTimestamp)
                .foregroundStyle(Color.dsAction)
                .tappableTarget()
        }
        .buttonStyle(.plain)
        .disabled(!model.hasAudio)
        .accessibilityLabel(L10n.Summary.listen(time.clock))
        .accessibilityIdentifier("summary.source")
    }
}
