import DesignSystem
import Domain
import Localization
import SwiftUI

/// What a meeting's transcription is doing, while it runs. The same card on every tab, so the person sees it
/// where they land after recording, and never has to guess whether the app is working or stuck.
///
/// It shows the steps and where the work is, a bar that fills when the fraction is real and keeps moving when it
/// is not, the time that has passed, and, once there is enough to measure, the time left.
public struct TranscriptionStatusCard: View {
    private let progress: JobProgress
    private let onCancel: () -> Void

    public init(progress: JobProgress, onCancel: @escaping () -> Void) {
        self.progress = progress
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.Transcript.workingTitle)
                    .font(.dsHeading)
                    .foregroundStyle(Color.dsPrimaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Spacing.small)
                if progress.isMeasurable {
                    Text(progress.fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.dsMeta.monospacedDigit())
                        .foregroundStyle(Color.dsPrimaryText)
                        .contentTransition(.numericText())
                }
            }

            if let waiting {
                StatusBadge(waiting.title, tone: waiting.tone, symbol: waiting.symbol)
            } else {
                ActivityBar(fraction: progress.isMeasurable ? progress.fraction : nil)
            }

            StepList(progress.steps, labels: .standard)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let line = timing(at: context.date) {
                    Text(line)
                        .font(.dsNote.monospacedDigit())
                        .foregroundStyle(Color.dsSecondaryText)
                        .contentTransition(.numericText())
                }
            }

            Text(note)
                .font(.dsNote)
                .foregroundStyle(Color.dsSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button(L10n.Common.cancel, role: .cancel, action: onCancel)
                .secondaryAction(.regular)
                .accessibilityIdentifier("transcript.cancel")
        }
        .dsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transcript.status")
    }

    private struct Waiting {
        let title: String
        let tone: StatusBadge.Tone
        let symbol: String
    }

    private var waiting: Waiting? {
        switch progress.phase {
        case .queued: Waiting(title: L10n.Transcript.queued, tone: .waiting, symbol: "hourglass")
        case .waitingForDevice:
            Waiting(title: L10n.Transcript.waitingForDevice, tone: .attention, symbol: "thermometer.medium")
        case .waitingForPower: Waiting(title: L10n.Transcript.waitingForPower, tone: .attention, symbol: "bolt.fill")
        case .interrupted:
            Waiting(title: L10n.Transcript.interrupted, tone: .attention, symbol: "exclamationmark.triangle.fill")
        case .preparing, .transcribing, .separatingSpeakers: nil
        }
    }

    private var note: String {
        switch progress.phase {
        case .queued: L10n.Transcript.queuedNote
        case .waitingForDevice: L10n.Transcript.deviceNote
        case .waitingForPower: L10n.Transcript.powerNote
        case .interrupted: L10n.Transcript.interruptedNote
        case .preparing: L10n.Transcript.prepareNote
        case .separatingSpeakers: L10n.Transcript.speakersNote
        case .transcribing: L10n.Transcript.leaveNote
        }
    }

    /// Elapsed time, and the time left once it can be measured. Nothing while waiting: no work is going on.
    private func timing(at now: Date) -> String? {
        guard waiting == nil, let started = progress.phaseStartedAt else { return nil }
        let elapsed = L10n.Feedback.elapsed(Self.format(now.timeIntervalSince(started)))
        guard let left = progress.estimatedRemaining(at: now) else { return elapsed }
        return [elapsed, L10n.Feedback.remaining(Self.format(left))].joined(separator: " · ")
    }

    static func format(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds.rounded())).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2),
        )
    }
}

public extension ProcessStepLabels {
    static var standard: ProcessStepLabels {
        ProcessStepLabels(
            waiting: L10n.Feedback.stepWaiting, active: L10n.Feedback.stepActive, done: L10n.Feedback.stepDone,
        )
    }
}

public extension JobProgress {
    /// The steps of a transcription, with where this job is.
    var steps: [ProcessStep] {
        var order: [(step: ProcessStep, phase: Phase)] = [
            (ProcessStep(id: "prepare", title: L10n.Transcript.stepPrepare, state: .waiting), .preparing),
            (ProcessStep(id: "transcribe", title: L10n.Transcript.stepTranscribe, state: .waiting), .transcribing),
        ]
        if includesSpeakers {
            order.append(
                (
                    ProcessStep(id: "speakers", title: L10n.Transcript.stepSpeakers, state: .waiting),
                    .separatingSpeakers,
                ),
            )
        }
        let current = order.firstIndex { $0.phase == phase }
        return order.enumerated().map { index, entry in
            let state: ProcessStep.State = if let current {
                index < current ? .done : index == current ? .active : .waiting
            } else {
                .waiting
            }
            return ProcessStep(id: entry.step.id, title: entry.step.title, state: state)
        }
    }

    /// A badge for a list row: a ring that fills while text is being written, and a symbol while waiting.
    @MainActor var badge: StatusBadge {
        switch phase {
        case .transcribing: StatusBadge(statusText, tone: .working, fraction: fraction)
        case .preparing, .separatingSpeakers: StatusBadge(statusText, tone: .working)
        case .queued: StatusBadge(statusText, tone: .waiting, symbol: "hourglass")
        case .waitingForDevice: StatusBadge(statusText, tone: .attention, symbol: "thermometer.medium")
        case .waitingForPower: StatusBadge(statusText, tone: .attention, symbol: "bolt.fill")
        case .interrupted: StatusBadge(statusText, tone: .attention, symbol: "exclamationmark.triangle.fill")
        }
    }
}
