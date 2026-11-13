import Foundation

// MARK: - When the engine fails

/// A failure must never reach the transcript as silence, and never mark it as done. The window is tried again with
/// the model loaded again. If it still fails, the job waits, with what was saved so far, until the person is back.
public extension TranscriptionCoordinator {
    /// Tries again the jobs the engine failed on. Runs when the app comes to the front, since the usual cause is
    /// iOS holding back the hardware from an app in the background, or memory that is free again.
    func retryHeld() async {
        guard !held.isEmpty else { return }
        for id in held {
            report(id, .queued, progress[id]?.fraction ?? 0)
        }
        held.removeAll()
        await resumePausedIfPossible()
    }
}

extension TranscriptionCoordinator {
    /// Keeps a job the engine failed on, never marking its transcript as done. What was saved stays, and the job
    /// goes on from its checkpoint later. Its model is unloaded, since a broken load is a common cause.
    func hold(_ original: TranscriptionJob) async {
        let id = original.recordingID
        var job = await (try? store.job(for: id)) ?? original
        job.state = .queued
        try? await store.save(job)
        held.insert(id)
        await unloadEngine()
        let duration = await (try? source.duration(of: files.audioFile(for: id))) ?? 0
        report(id, .interrupted, fraction(job, duration))
    }

    /// One window, tried a second time with the model loaded again. A failure never reaches the transcript as
    /// silence: the window is saved only when the engine finished all of it.
    func transcribe(
        _ window: AudioWindow,
        of job: TranscriptionJob,
        engine: any TranscriptionEngine,
        hints: [String],
        duration: TimeInterval,
    ) async throws -> WindowResult {
        let id = job.recordingID
        let onProgress: @Sendable (Double) -> Void = { [weak self] part in
            let position = window.start + (window.end - window.start) * min(max(part, 0), 1)
            Task { await self?.reportWithin(id, position: position, duration: duration) }
        }
        do {
            return try await engine.transcribe(window, language: job.language, hints: hints, progress: onProgress)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard let resolved = models(job.modelID) else { throw error }
            await unloadEngine()
            try await engine.prepare(model: resolved.model, folder: resolved.folder)
            loaded = (resolved.model.runtime, job.modelID)
            return try await engine.transcribe(window, language: job.language, hints: hints, progress: onProgress)
        }
    }

    /// Progress from inside a window. It arrives a moment late, so it only ever moves the bar forward, and only
    /// while text is still being written.
    private func reportWithin(_ id: RecordingID, position: TimeInterval, duration: TimeInterval) async {
        guard duration > 0, let current = progress[id], current.phase == .transcribing else { return }
        let value = min(position / duration, 1)
        guard value > current.fraction else { return }
        report(id, .transcribing, value)
        await lease.update(progress: value)
    }
}
