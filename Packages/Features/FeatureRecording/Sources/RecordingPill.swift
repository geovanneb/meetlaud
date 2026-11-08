import AppRouting
import DesignSystem
import Domain
import Localization
import SwiftUI

/// Shows the recording in progress on every screen, once the recorder is minimized.
public struct RecordingPill: View {
    private let controller: RecordingController
    @Environment(AppRouter.self) private var router
    /// Counts taps that open the recorder, so each one gets a light tap back.
    @State private var opens = 0

    public init(controller: RecordingController) {
        self.controller = controller
    }

    private var isPaused: Bool {
        if case .paused = controller.snapshot.status {
            true
        } else {
            false
        }
    }

    private var isVisible: Bool {
        controller.snapshot.status.isActive && !router.isRecorderPresented
    }

    public var body: some View {
        Group {
            if isVisible {
                pill.riseTransition()
            }
        }
        .motion(Motion.standard, value: isVisible)
    }

    /// Built like the prompt bar under it: the whole capsule is the button, at least as tall as the bar, and the
    /// glass reacts under the finger. Before, only the text line could be tapped and nothing showed a press, so a
    /// tap felt missed.
    private var pill: some View {
        HStack(spacing: 0) {
            Button {
                opens += 1
                router.isRecorderPresented = true
            } label: {
                HStack(spacing: Spacing.small) {
                    Circle()
                        .fill(isPaused ? Color.dsSecondaryText : Color.dsRecord)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(controller.snapshot.recorded.clock)
                        .font(.dsRowTitle.monospacedDigit())
                    Text(isPaused ? L10n.Recorder.statusPaused : L10n.Recorder.statusRecording)
                        .font(.dsMeta)
                        .foregroundStyle(Color.dsSecondaryText)
                    Spacer(minLength: 0)
                }
                .padding(.leading, PromptMetrics.textInset)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("recorder.pill")

            Button(
                isPaused ? L10n.Recorder.resume : L10n.Recorder.pause,
                systemImage: isPaused ? "play.fill" : "pause.fill",
            ) {
                controller.togglePause()
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, maxHeight: .infinity)
            .padding(.trailing, Spacing.compact)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(minHeight: PromptMetrics.minimumHeight)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular.interactive(), in: .capsule)
        .sensoryFeedback(.impact(weight: .light), trigger: opens)
        .promptPlacement()
    }
}
