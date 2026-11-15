import BackgroundTasks
import Domain
import Foundation

/// Asks iOS to let a transcription keep going after the user leaves the app, with progress in the system UI.
/// iOS can refuse or end this at any time. Jobs are resumable, so nothing depends on it.
///
/// iOS ends a continued processing task that stops reporting progress, and shows "Task failed" for it. Progress only
/// arrives once per audio window, and not at all while the model is prepared or voices are separated, which can take
/// minutes. So the lease reports in fine steps, and while the queue is working it also moves a little on its own.
@MainActor
final class ContinuedProcessingLease: BackgroundWorkLease {
    /// Fine enough that every audio window of a long meeting moves the count.
    private static let totalUnits: Int64 = 10000
    /// Transcription fills up to here. The rest is for the steps that report nothing: separating voices and saving.
    private static let transcriptionUnits: Int64 = 9000
    private static let heartbeatInterval: Duration = .seconds(10)

    private var task: BGContinuedProcessingTask?
    private var heartbeat: Task<Void, Never>?
    /// The task this lease asked for last. Nil when nothing is requested.
    private var requested: String?

    func begin(title: String) async {
        guard requested == nil else { return }
        // Must match BGTaskSchedulerPermittedIdentifiers, which starts with the bundle identifier.
        guard let prefix = Bundle.main.bundleIdentifier else { return }
        let identifier = "\(prefix).transcribe.\(UUID().uuidString)"
        requested = identifier
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
            requested = nil
        }
    }

    private func attach(_ task: BGContinuedProcessingTask) {
        // The queue can end before iOS starts the task, or a newer request can replace it. Either way nothing is left
        // to report for this one, so it ends right away.
        guard task.identifier == requested else {
            task.setTaskCompleted(success: true)
            return
        }
        self.task = task
        task.progress.totalUnitCount = Self.totalUnits
        // iOS calls this on a background queue, not on the queue the task was registered with, so it hops to the
        // main actor instead of assuming it is already there. Asserting crashed the app each time iOS ended the task.
        task.expirationHandler = { [weak self] in
            Task { @MainActor in self?.finish(success: false) }
        }
        startHeartbeat()
    }

    func update(progress: Double) async {
        let units = Int64((min(max(progress, 0), 1) * Double(Self.transcriptionUnits)).rounded(.down))
        advance(to: units)
    }

    func end() async {
        finish(success: true)
    }

    /// The queue is still working between real updates, so the count creeps forward one unit at a time. It never
    /// reaches the end by itself: only `end()` completes the task.
    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeatInterval)
                guard !Task.isCancelled, let self, let task else { return }
                advance(to: task.progress.completedUnitCount + 1)
            }
        }
    }

    /// Progress only moves forward, and stops one unit short of done.
    private func advance(to units: Int64) {
        guard let task else { return }
        let capped = min(units, Self.totalUnits - 1)
        if capped > task.progress.completedUnitCount {
            task.progress.completedUnitCount = capped
        }
    }

    private func finish(success: Bool) {
        heartbeat?.cancel()
        heartbeat = nil
        if let task {
            if success {
                task.progress.completedUnitCount = Self.totalUnits
            }
            task.setTaskCompleted(success: success)
        }
        task = nil
        requested = nil
    }
}
