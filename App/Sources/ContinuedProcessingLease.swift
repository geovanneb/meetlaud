import BackgroundTasks
import Domain
import Foundation

/// Asks iOS to let a transcription keep going after the user leaves the app, with progress in the system UI.
/// iOS can refuse or end this at any time. Jobs are resumable, so nothing depends on it.
@MainActor
final class ContinuedProcessingLease: BackgroundWorkLease {
    private var task: BGContinuedProcessingTask?
    private var isRequested = false

    func begin(title: String) async {
        guard !isRequested else { return }
        isRequested = true
        let identifier = "com.meetlaud.app.transcribe.\(UUID().uuidString)"
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            guard let task = task as? BGContinuedProcessingTask else { return }
            MainActor.assumeIsolated {
                self?.attach(task)
            }
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: "")
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            isRequested = false
        }
    }

    private func attach(_ task: BGContinuedProcessingTask) {
        self.task = task
        task.progress.totalUnitCount = 100
        task.expirationHandler = { [weak self] in
            MainActor.assumeIsolated { self?.finish(success: false) }
        }
    }

    func update(progress: Double) async {
        task?.progress.completedUnitCount = Int64(progress * 100)
    }

    func end() async {
        finish(success: true)
    }

    private func finish(success: Bool) {
        task?.setTaskCompleted(success: success)
        task = nil
        isRequested = false
    }
}
