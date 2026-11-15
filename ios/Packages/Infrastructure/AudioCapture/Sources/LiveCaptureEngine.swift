@preconcurrency import AVFAudio
import Domain
import Foundation

public enum CaptureError: Error {
    case noInput
}

/// Captures the microphone with AVAudioEngine.
///
/// Access to mutable state is serialized by `queue`. The audio itself flows through `CapturePipeline`.
public final class LiveCaptureEngine: AudioCaptureEngine, @unchecked Sendable {
    public let events: AsyncStream<CaptureEvent>
    private let continuation: AsyncStream<CaptureEvent>.Continuation
    private let pipeline: CapturePipeline
    private let queue = DispatchQueue(label: "com.meetlaud.capture")
    private let observerQueue: OperationQueue

    private var engine = AVAudioEngine()
    private var isCapturing = false
    private var isInterrupted = false
    private var observers: [any NSObjectProtocol] = []

    public init() {
        let (stream, continuation) = AsyncStream.makeStream(
            of: CaptureEvent.self,
            bufferingPolicy: .bufferingNewest(64),
        )
        events = stream
        self.continuation = continuation
        pipeline = CapturePipeline { continuation.yield($0) }
        observerQueue = OperationQueue()
        observerQueue.underlyingQueue = queue
        observeSession()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - AudioCaptureEngine

    public func start(directory: URL) async throws {
        try await perform {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .defaultToSpeaker])
            try session.setActive(true)
            self.pipeline.begin(directory: directory)
            try self.startEngine()
            self.isCapturing = true
            self.isInterrupted = false
        }
    }

    public func pause() async {
        pipeline.setPaused(true)
    }

    public func resume() async throws {
        try await perform {
            if self.isInterrupted || !self.engine.isRunning {
                try AVAudioSession.sharedInstance().setActive(true)
                try self.startEngine()
                self.isInterrupted = false
            }
            self.pipeline.setPaused(false)
        }
    }

    public func stop() async throws {
        try await perform {
            self.isCapturing = false
            self.stopEngine()
            try self.pipeline.finish()
        }
    }

    public func deactivate() async {
        try? await perform {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    public func availableInputs() async -> [AudioInput] {
        (AVAudioSession.sharedInstance().availableInputs ?? []).map {
            AudioInput(id: $0.uid, name: $0.portName)
        }
    }

    public func selectInput(_ input: AudioInput) async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setPreferredInput(session.availableInputs?.first { $0.uid == input.id })
    }

    // MARK: - Engine

    /// Runs on the private queue, so that session calls, which can block, never touch the caller's thread.
    private func perform(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func startEngine() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noInput }

        pipeline.prepare(inputFormat: format)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [pipeline] buffer, _ in
            pipeline.process(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private func stopEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    // MARK: - System events

    private func observeSession() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: observerQueue,
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init)
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init)
            self?.handleInterruption(type, shouldResume: options?.contains(.shouldResume) ?? false)
        })

        // A new route, such as AirPods, changes the input format and stops the engine.
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: observerQueue,
        ) { [weak self] _ in
            self?.restartAfterConfigurationChange()
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: observerQueue,
        ) { [weak self] _ in
            self?.rebuildAfterMediaReset()
        })
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType?, shouldResume: Bool) {
        guard isCapturing else { return }
        switch type {
        case .began:
            isInterrupted = true
            continuation.yield(.interruptionBegan)
        case .ended:
            continuation.yield(.interruptionEnded(shouldResume: shouldResume))
        default:
            break
        }
    }

    private func restartAfterConfigurationChange() {
        guard isCapturing, !isInterrupted else { return }
        do {
            stopEngine()
            try startEngine()
        } catch {
            continuation.yield(.failed(error.localizedDescription))
        }
    }

    private func rebuildAfterMediaReset() {
        guard isCapturing else { return }
        engine = AVAudioEngine()
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try startEngine()
        } catch {
            continuation.yield(.failed(error.localizedDescription))
        }
    }
}

public struct LiveMicrophonePermission: MicrophonePermission {
    public init() {}

    public var access: MicrophoneAccess {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .undetermined
        }
    }

    public func request() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
