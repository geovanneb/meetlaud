import ActivityKit
import AppIntents
import Localization
import SwiftUI
import WidgetKit

@main
struct MeetlaudWidgets: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
        RecordControl()
        RecordWidget()
        MeetingsWidget()
    }
}

struct RecordingLiveActivity: Widget {
    private let red = Color(red: 0.9, green: 0.28, blue: 0.3)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    timer(context.state)
                        .font(.title2.weight(.semibold).monospacedDigit())
                    Text(status(context.state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                controls(context.state)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    timer(context.state)
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(status(context.state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    controls(context.state)
                }
            } compactLeading: {
                Image(systemName: "waveform")
                    .foregroundStyle(red)
            } compactTrailing: {
                timer(context.state)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundStyle(red)
            }
        }
    }

    @ViewBuilder
    private func timer(_ state: RecordingActivityAttributes.ContentState) -> some View {
        if state.phase == .recording {
            Text(timerInterval: state.timerStart ... .distantFuture, countsDown: false)
        } else {
            Text(Duration.seconds(state.recorded).formatted(.time(pattern: .hourMinuteSecond)))
        }
    }

    private func status(_ state: RecordingActivityAttributes.ContentState) -> String {
        switch state.phase {
        case .recording: L10n.Recorder.statusRecording
        case .paused: L10n.Recorder.statusPaused
        case .interrupted: L10n.Recorder.statusInterrupted
        case .finishing: L10n.Recorder.statusFinishing
        }
    }

    @ViewBuilder
    private func controls(_ state: RecordingActivityAttributes.ContentState) -> some View {
        if state.phase != .finishing {
            HStack(spacing: 10) {
                Button(intent: MarkMomentIntent()) {
                    Image(systemName: "flag.fill")
                        .accessibilityLabel(L10n.Recorder.flag)
                }
                Button(intent: TogglePauseIntent()) {
                    Image(systemName: state.phase == .recording ? "pause.fill" : "play.fill")
                        .accessibilityLabel(state.phase == .recording ? L10n.Recorder.pause : L10n.Recorder.resume)
                }
                Button(intent: StopRecordingIntent()) {
                    Image(systemName: "stop.fill")
                        .foregroundStyle(red)
                        .accessibilityLabel(L10n.Recorder.stop)
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
        }
    }
}
