import Foundation

public enum RecordingError: Error, Equatable {
    case alreadyRecording
    case noActiveRecording
}

/// Owns the life of a recording: capture, pauses, interruptions, markers, and saving.
///
/// The rule behind every method: state that matters reaches the database first, so that a crash at any point
/// leaves something `recoverInterrupted()` can finish.
public actor RecordingCoordinator {
    public enum Limits {
        /// Warn the user.
        public static let lowStorageBytes: Int64 = 500_000_000
        /// Stop safely, while there is still room to save.
        public static let criticalStorageBytes: Int64 = 100_000_000
        /// Checking storage on every level update would be wasteful.
        static let storageCheckInterval: TimeInterval = 5
        /// Live Activity updates have a budget, and the timer there runs by itself.
        static let activityUpdateInterval: TimeInterval = 30
    }

    private let engine: any AudioCaptureEngine
    private let store: any RecordingStore
    private let files: any RecordingFiles
    private let assembler: any AudioAssembler
    private let activity: any RecordingActivityPresenter
    private let now: @Sendable () -> Date

    private var snapshot = RecordingSnapshot() {
        didSet { continuation.yield(snapshot) }
    }

    private var current: Recording?
    private var pausedAt: Date?
    private var lastStorageCheck: TimeInterval = 0
    private var lastActivityUpdate: TimeInterval = 0
    private var listener: Task<Void, Never>?

    public nonisolated let snapshots: AsyncStream<RecordingSnapshot>
    private let continuation: AsyncStream<RecordingSnapshot>.Continuation

    public init(
        engine: any AudioCaptureEngine,
        store: any RecordingStore,
        files: any RecordingFiles,
        assembler: any AudioAssembler,
        activity: any RecordingActivityPresenter,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.engine = engine
        self.store = store
        self.files = files
        self.assembler = assembler
        self.activity = activity
        self.now = now
        (snapshots, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    public var currentSnapshot: RecordingSnapshot {
        snapshot
    }

    // MARK: - Capture

    @discardableResult
    public func start(title: String, attendees: [String] = []) async throws -> RecordingID {
        guard !snapshot.status.isActive else { throw RecordingError.alreadyRecording }
        listenToEngineIfNeeded()

        let recording = Recording(title: title, createdAt: now(), status: .capturing, attendees: attendees)
        try await store.insert(recording)
        do {
            try await engine.start(directory: files.segmentsDirectory(for: recording.id))
        } catch {
            try? await store.delete(recording.id)
            try? files.removeAll(for: recording.id)
            throw error
        }

        current = recording
        lastStorageCheck = 0
        lastActivityUpdate = 0
        var next = RecordingSnapshot()
        next.status = .recording
        next.recordingID = recording.id
        next.title = title
        next.isStorageLow = files.availableBytes() < Limits.lowStorageBytes
        snapshot = next

        await activity.begin(title: title)
        return recording.id
    }

    public func pause() async {
        guard snapshot.status == .recording else { return }
        await engine.pause()
        pausedAt = now()
        snapshot.status = .paused(.user)
        await activity.update(status: snapshot.status, recorded: snapshot.recorded)
    }

    public func resume() async throws {
        guard case let .paused(reason) = snapshot.status else { return }
        try await engine.resume()
        await recordPause(reason: reason)
        snapshot.status = .recording
        snapshot.needsManualResume = false
        await activity.update(status: snapshot.status, recorded: snapshot.recorded)
    }

    @discardableResult
    public func stop() async throws -> Recording {
        guard var recording = current, snapshot.status.isActive, snapshot.status != .finishing else {
            throw RecordingError.noActiveRecording
        }
        if case let .paused(reason) = snapshot.status {
            await recordPause(reason: reason)
        }
        snapshot.status = .finishing
        await activity.update(status: .finishing, recorded: snapshot.recorded)

        defer {
            current = nil
            snapshot = RecordingSnapshot()
        }

        do {
            // A failure here leaves the recording in `.capturing` with its segments, for recovery.
            try await engine.stop()
            recording.duration = try await assembler.assemble(
                segments: files.segmentsDirectory(for: recording.id),
                into: files.audioFile(for: recording.id),
            )
            recording.status = .ready
            try await store.update(recording)
            try? files.removeSegments(for: recording.id)
        } catch {
            await engine.deactivate()
            await activity.end()
            throw error
        }

        await engine.deactivate()
        await activity.end()
        return recording
    }

    // MARK: - Markers

    @discardableResult
    public func addMarker(kind: MarkerKind, text: String? = nil, attachment: String? = nil) async throws -> Marker {
        guard let current else { throw RecordingError.noActiveRecording }
        let marker = Marker(
            recordingID: current.id,
            time: snapshot.recorded,
            kind: kind,
            text: text,
            attachment: attachment,
        )
        try await store.insert(marker)
        snapshot.markers.append(marker)
        return marker
    }

    /// Saves the photo first, so that a marker never points to a missing file.
    @discardableResult
    public func addPhoto(_ data: Data) async throws -> Marker {
        guard let current else { throw RecordingError.noActiveRecording }
        let name = "\(UUID().uuidString).jpg"
        let directory = try files.attachmentsDirectory(for: current.id)
        try data.write(to: directory.appending(path: name), options: .atomic)
        return try await addMarker(kind: .photo, attachment: name)
    }

    // MARK: - Input

    public func availableInputs() async -> [AudioInput] {
        await engine.availableInputs()
    }

    public func selectInput(_ input: AudioInput) async throws {
        try await engine.selectInput(input)
    }

    // MARK: - Recovery

    /// Finishes recordings that a crash left behind. Returns the ones it saved.
    @discardableResult
    public func recoverInterrupted() async throws -> [Recording] {
        var recovered: [Recording] = []
        for var recording in try await store.recordings(status: .capturing) where recording.id != current?.id {
            guard files.hasSegments(for: recording.id) else {
                try await store.delete(recording.id)
                try? files.removeAll(for: recording.id)
                continue
            }
            do {
                recording.duration = try await assembler.assemble(
                    segments: files.segmentsDirectory(for: recording.id),
                    into: files.audioFile(for: recording.id),
                )
            } catch {
                // Keep the segments. A later launch, or a future version, can try again.
                continue
            }
            recording.status = .ready
            recording.wasRecovered = true
            try await store.update(recording)
            try? files.removeSegments(for: recording.id)
            recovered.append(recording)
        }
        return recovered
    }

    // MARK: - Engine events

    private func listenToEngineIfNeeded() {
        guard listener == nil else { return }
        let events = engine.events
        listener = Task { [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        }
    }

    private func handle(_ event: CaptureEvent) async {
        guard current != nil else { return }
        switch event {
        case let .progress(recorded, level):
            await handleProgress(recorded: recorded, level: level)
        case .interruptionBegan:
            await handleInterruptionBegan()
        case let .interruptionEnded(shouldResume):
            await handleInterruptionEnded(shouldResume: shouldResume)
        case .failed:
            // The samples already written are safe. Stopping saves them, instead of pretending to record.
            await handleInterruptionBegan()
            snapshot.needsManualResume = true
        }
    }

    private func handleProgress(recorded: TimeInterval, level: Float) async {
        snapshot.recorded = recorded
        snapshot.level = level

        if recorded - lastActivityUpdate >= Limits.activityUpdateInterval {
            lastActivityUpdate = recorded
            await activity.update(status: snapshot.status, recorded: recorded)
        }

        guard recorded - lastStorageCheck >= Limits.storageCheckInterval else { return }
        lastStorageCheck = recorded
        let available = files.availableBytes()
        snapshot.isStorageLow = available < Limits.lowStorageBytes
        if available < Limits.criticalStorageBytes {
            _ = try? await stop()
        }
    }

    private func handleInterruptionBegan() async {
        guard snapshot.status == .recording else { return }
        pausedAt = now()
        snapshot.status = .paused(.interruption)
        await activity.update(status: snapshot.status, recorded: snapshot.recorded)
    }

    private func handleInterruptionEnded(shouldResume _: Bool) async {
        guard snapshot.status == .paused(.interruption) else { return }
        // Try even when the system does not suggest it. The worst outcome is showing Resume.
        do {
            try await resume()
        } catch {
            snapshot.needsManualResume = true
            await activity.update(status: snapshot.status, recorded: snapshot.recorded)
        }
    }

    private func recordPause(reason: PauseReason) async {
        guard let current, let pausedAt else { return }
        self.pausedAt = nil
        let pause = PauseSpan(
            recordingID: current.id,
            position: snapshot.recorded,
            duration: now().timeIntervalSince(pausedAt),
            reason: reason,
        )
        try? await store.insert(pause)
    }
}
