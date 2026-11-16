@preconcurrency import ActivityKit
import Domain
import Foundation

/// Shows the recording on the Lock Screen and Dynamic Island. If the user turned Live Activities off, recording
/// goes on without them, so failures here are ignored on purpose.
@MainActor
final class LiveActivityPresenter: RecordingActivityPresenter {
    private var activity: Activity<RecordingActivityAttributes>?

    func begin(title: String) async {
        await endStale()
        let state = RecordingActivityAttributes.ContentState(phase: .recording, timerStart: .now, recorded: 0)
        activity = try? Activity.request(
            attributes: RecordingActivityAttributes(title: title),
            content: ActivityContent(state: state, staleDate: nil),
        )
    }

    func update(status: CaptureStatus, recorded: TimeInterval) async {
        let phase: RecordingActivityAttributes.ContentState.Phase = switch status {
        case .paused(.user): .paused
        case .paused(.interruption): .interrupted
        case .finishing: .finishing
        default: .recording
        }
        let state = RecordingActivityAttributes.ContentState(
            phase: phase,
            timerStart: Date.now.addingTimeInterval(-recorded),
            recorded: recorded,
        )
        await activity?.update(ActivityContent(state: state, staleDate: nil))
    }

    func end() async {
        await activity?.end(nil, dismissalPolicy: .immediate)
        activity = nil
    }

    /// A crash can leave an activity on screen with nothing behind it.
    func endStale() async {
        for activity in Activity<RecordingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
