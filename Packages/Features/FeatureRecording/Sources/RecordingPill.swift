import AppRouting
import DesignSystem
import Domain
import Localization
import SwiftUI

/// Shows the recording in progress on every screen, once the recorder is minimized.
public struct RecordingPill: View {
    private let controller: RecordingController
    @Environment(AppRouter.self) private var router

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

    private var pill: some View {
        HStack(spacing: Spacing.small) {
            Button {
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
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .padding(.leading, PromptMetrics.textInset)
        .padding(.trailing, Spacing.compact)
        .padding(.vertical, Spacing.xSmall)
        .glassEffect(.regular, in: .capsule)
        .promptPlacement()
    }
}
