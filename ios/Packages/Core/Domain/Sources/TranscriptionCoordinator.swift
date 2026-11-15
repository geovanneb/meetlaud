import Foundation

/// Runs transcription jobs, one at a time, and keeps them safe across crashes, heat, and closed apps.
public actor TranscriptionCoordinator {
    private let vocabulary: @Sendable () -> [VocabularyEntry]
    public typealias ModelResolver = @Sendable (String) -> (model: ModelDescriptor, folder: URL?)?
    public typealias EngineResolver = @Sendable (ModelRuntime) -> (any TranscriptionEngine)?

    let store: any TranscriptStore
    private let usage: any ModelUsageStore
    private let recordings: any RecordingStore
    let files: any RecordingFiles
    let source: any AudioWindowSource
    private let device: any DeviceMonitor
    let lease: any BackgroundWorkLease
    let arbiter: ModelArbiter
    let speakers: SpeakerPipeline?
    private let onFinished: @Sendable (RecordingID) async -> Void
    let models: ModelResolver
    private let engines: EngineResolver
    let now: @Sendable () -> Date

    var progress: [RecordingID: JobProgress] = [:] {
        didSet { continuation.yield(progress) }
    }

    private var worker: Task<Void, Never>?
    private var deviceWatcher: Task<Void, Never>?
    var loaded: (runtime: ModelRuntime, modelID: String)?
    /// Jobs the engine failed on, even after a second try. They wait for `retryHeld()`, which the app calls when the
    /// person comes back, so that a job that keeps failing does not run again on every battery change.
    var held: Set<RecordingID> = []
    /// Whether the current job ends by separating voices, so screens can show that step from the start.
    var includesSpeakers = false

    public nonisolated let updates: AsyncStream<[RecordingID: JobProgress]>
    private let continuation: AsyncStream<[RecordingID: JobProgress]>.Continuation

    public init(
        store: any TranscriptStore,
        usage: any ModelUsageStore,
        recordings: any RecordingStore,
        files: any RecordingFiles,
        source: any AudioWindowSource,
        device: any DeviceMonitor,
        lease: any BackgroundWorkLease,
        arbiter: ModelArbiter,
        speakers: SpeakerPipeline? = nil,
        vocabulary: @escaping @Sendable () -> [VocabularyEntry] = { [] },
        onFinished: @escaping @Sendable (RecordingID) async -> Void = { _ in },
        models: @escaping ModelResolver,
        engines: @escaping EngineResolver,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.store = store
        self.vocabulary = vocabulary
        self.usage = usage
        self.recordings = recordings
        self.files = files
        self.source = source
        self.device = device
        self.lease = lease
        self.arbiter = arbiter
        self.speakers = speakers
        self.onFinished = onFinished
        self.models = models
        self.engines = engines
        self.now = now
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    public var currentProgress: [RecordingID: JobProgress] {
        progress
    }

    // MARK: - Queue

    /// Starts over with this model. An earlier transcript is replaced once the first text is saved.
    /// `whenCharging` holds the job until the device is on a charger and not hot.
    public func enqueue(
        _ id: RecordingID,
        modelID: String,
        language: String?,
        whenCharging: Bool = false,
    ) async throws {
        try await keepCurrentTranscript(of: id)
        try await store.deleteTranscript(for: id)
        let job = TranscriptionJob(
            recordingID: id, modelID: modelID, language: language, state: whenCharging ? .waitingForPower : .queued,
        )
        try await store.save(job)
        try await store.save(Transcript(recordingID: id, modelID: modelID, language: language, isComplete: false))
        report(id, whenCharging ? .waitingForPower : .queued, 0)
        if whenCharging {
            await resumePausedIfPossible()
        } else {
            startWorkerIfNeeded()
        }
    }

    public func cancel(_ id: RecordingID) async throws {
        held.remove(id)
        try await store.deleteJob(for: id)
        progress[id] = nil
    }

    /// Runs at launch. A job still marked as running means that the app died in the middle of it.
    public func resumeInterrupted(countKills: Bool = true) async throws {
        for var job in try await store.jobs() {
            if job.state == .running {
                if countKills {
                    try await usage.insert(ModelRunStat(
                        modelID: job.modelID, audioDuration: 0, wallTime: 0, outcome: .killed, date: now(),
                    ))
                }
                job.state = .queued
                try await store.save(job)
            }
            let duration = await (try? source.duration(of: files.audioFile(for: job.recordingID))) ?? 0
            report(
                job.recordingID,
                job.state == .waitingForPower ? .waitingForPower : .queued,
                duration > 0 ? min(job.checkpoint / duration, 1) : 0,
            )
        }
        await resumePausedIfPossible()
    }

    private func startWorkerIfNeeded() {
        watchDeviceIfNeeded()
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drainQueue()
        }
    }

    private func drainQueue() async {
        // Held for the whole queue, so that the model stays loaded between jobs and nothing else can unload it.
        await arbiter.acquire()
        while let job = await nextJob() {
            do {
                try await run(job)
            } catch is CancellationError {
                break
            } catch TranscriptionError.modelNotInstalled, TranscriptionError.missingModelFiles {
                // Nothing can bring the model back by itself. The text saved so far stays.
                try? await store.deleteJob(for: job.recordingID)
                progress[job.recordingID] = nil
            } catch {
                await hold(job)
            }
        }
        await unloadEngine()
        await arbiter.release()
        await lease.end()
        worker = nil
        // A job can arrive in the moment between the last check and clearing the worker.
        if await nextJob() != nil {
            startWorkerIfNeeded()
        }
    }

    private func nextJob() async -> TranscriptionJob? {
        let waiting = await (try? store.jobs()) ?? []
        return waiting.first { ($0.state == .queued || $0.state == .running) && !held.contains($0.recordingID) }
    }

    // MARK: - Running

    private func run(_ original: TranscriptionJob) async throws {
        var job = original
        let id = job.recordingID
        guard let resolved = models(job.modelID), let engine = engines(resolved.model.runtime) else {
            throw TranscriptionError.modelNotInstalled
        }
        let file = files.audioFile(for: id)
        let duration = try await source.duration(of: file)

        guard try await waitForDevice(job: job, duration: duration) else { return }

        job.state = .running
        try await store.save(job)
        try await lease.begin(title: recordings.recording(id)?.title ?? "")

        includesSpeakers = await speakers?.isAvailable() ?? false
        report(id, .preparing, fraction(job, duration))
        if loaded?.modelID != job.modelID {
            await unloadEngine()
            try await engine.prepare(model: resolved.model, folder: resolved.folder)
            loaded = (resolved.model.runtime, job.modelID)
        }

        let started = now()
        let startPosition = job.checkpoint
        guard let finished = try await transcribeWindows(of: job, engine: engine, file: file, duration: duration)
        else { return }
        // Done means the text reaches the end of the audio. Anything less is a job to finish, never a transcript
        // to call complete.
        guard finished.checkpoint >= duration - 1 else { throw TranscriptionError.audioUnavailable }

        try await separateSpeakers(id: id, file: file)
        try await store.save(Transcript(
            recordingID: id, modelID: job.modelID, language: finished.language, isComplete: true,
        ))
        try await store.deleteJob(for: id)
        progress[id] = nil
        try await usage.insert(ModelRunStat(
            modelID: job.modelID,
            audioDuration: duration - startPosition,
            wallTime: now().timeIntervalSince(started),
            outcome: .completed,
            date: now(),
        ))
        await onFinished(id)
    }

    /// Speakers are a bonus on top of the text. A failure here must never cost the transcript.
    private func separateSpeakers(id: RecordingID, file: URL) async throws {
        guard let speakers, await speakers.isAvailable() else { return }
        // Two heavy models at once is how iOS ends up killing the app.
        await unloadEngine()
        report(id, .separatingSpeakers, 1)
        do {
            try await speakers.run(id: id, file: file)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return
        }
    }

    /// Returns nil when the job stopped early, by being canceled or paused for heat.
    private func transcribeWindows(
        of original: TranscriptionJob,
        engine: any TranscriptionEngine,
        file: URL,
        duration: TimeInterval,
    ) async throws -> TranscriptionJob? {
        var job = original
        let id = job.recordingID
        let folder = try await recordings.recording(id)?.folderID
        let vocabulary = vocabulary().applying(to: folder)
        let hints = TranscriptionHints.from(vocabulary)
        for try await window in source.windows(of: file, from: job.checkpoint) {
            try Task.checkCancellation()
            guard try await store.job(for: id) != nil else { return nil }
            // The model is ready once the first window starts, so the screen moves on from preparing now, not a
            // whole window later.
            report(id, .transcribing, fraction(job, duration))
            let result = try await transcribe(window, of: job, engine: engine, hints: hints, duration: duration)

            job.checkpoint = window.end
            job.language = job.language ?? result.language
            try await store.append(result.segments(in: window, id: id, vocabulary: vocabulary), job: job)

            let value = fraction(job, duration)
            report(id, .transcribing, value)
            await lease.update(progress: value)

            // Stopping between windows loses nothing, since each one is already saved.
            guard await RightNow.evaluate(device.condition()).allowsHeavyWork else {
                try await pause(job, duration: duration)
                return nil
            }
        }
        return job
    }

    /// The one place progress changes. A phase keeps its start time while it lasts, so screens can show elapsed
    /// time and, once there is enough to measure, the time left.
    func report(_ id: RecordingID, _ phase: JobProgress.Phase, _ value: Double) {
        let previous = progress[id]
        let continues = previous?.phase == phase
        progress[id] = JobProgress(
            phase: phase,
            fraction: value,
            phaseStartedAt: continues ? previous?.phaseStartedAt : now(),
            phaseStartFraction: continues ? previous?.phaseStartFraction : value,
            includesSpeakers: includesSpeakers || (previous?.includesSpeakers ?? false),
        )
    }

    func fraction(_ job: TranscriptionJob, _ duration: TimeInterval) -> Double {
        duration > 0 ? min(job.checkpoint / duration, 1) : 0
    }

    func unloadEngine() async {
        if let loaded {
            await engines(loaded.runtime)?.unload()
        }
        loaded = nil
    }

    /// Frees memory when iOS asks. The next window loads the model again.
    public func handleMemoryWarning() async {
        if worker == nil {
            await unloadEngine()
        }
    }
}

// MARK: - Waiting for the device

extension TranscriptionCoordinator {
    private func waitForDevice(job: TranscriptionJob, duration: TimeInterval) async throws -> Bool {
        guard await RightNow.evaluate(device.condition()).allowsHeavyWork else {
            try await pause(job, duration: duration)
            return false
        }
        return true
    }

    private func pause(_ job: TranscriptionJob, duration: TimeInterval) async throws {
        var job = job
        job.state = .paused
        try await store.save(job)
        report(job.recordingID, .waitingForDevice, fraction(job, duration))
    }

    /// Jobs paused by heat come back by themselves when the device cools down.
    private func watchDeviceIfNeeded() {
        guard deviceWatcher == nil else { return }
        let changes = device.changes
        deviceWatcher = Task { [weak self] in
            for await _ in changes {
                await self?.resumePausedIfPossible()
            }
        }
    }

    /// Jobs waiting for a charger come back too, once there is one and the device is not hot.
    func resumePausedIfPossible() async {
        let condition = await device.condition()
        let rightNow = RightNow.evaluate(condition)
        guard rightNow.allowsHeavyWork else {
            watchDeviceIfNeeded()
            return
        }
        let powered = condition.isCharging && rightNow != .limited(.hot)
        for var job in await (try? store.jobs()) ?? [] {
            switch job.state {
            case .paused:
                job.state = .queued
            case .waitingForPower where powered:
                job.state = .queued
                report(job.recordingID, .queued, progress[job.recordingID]?.fraction ?? 0)
            default:
                continue
            }
            try? await store.save(job)
        }
        startWorkerIfNeeded()
    }
}

private extension WindowResult {
    func segments(in window: AudioWindow, id: RecordingID, vocabulary: [VocabularyEntry]) -> [TranscriptSegment] {
        segments
            // Only punctuation is a model that heard no speech.
            .filter { TranscriptCleanup.hasWords($0.text) }
            .map {
                TranscriptSegment(
                    recordingID: id,
                    start: window.start + $0.start,
                    end: window.start + $0.end,
                    text: VocabularyCorrector.apply(
                        vocabulary,
                        to: TranscriptCleanup.markRepeats($0.text.trimmingCharacters(in: .whitespacesAndNewlines)),
                    ),
                )
            }
    }
}
