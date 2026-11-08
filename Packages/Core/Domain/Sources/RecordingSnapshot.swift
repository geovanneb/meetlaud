import Foundation

public enum CaptureStatus: Hashable, Sendable {
    case idle
    case recording
    case paused(PauseReason)
    /// Encoding the final file. The audio is already safe on disk.
    case finishing

    public var isActive: Bool {
        self != .idle
    }
}

/// Everything the interface needs to draw the recording in progress.
public struct RecordingSnapshot: Hashable, Sendable {
    public var status: CaptureStatus = .idle
    public var recordingID: RecordingID?
    public var title = ""
    public var recorded: TimeInterval = 0
    /// Audio level from 0 to 1.
    public var level: Float = 0
    public var markers: [Marker] = []
    public var isStorageLow = false
    /// The system ended the interruption but would not let capture resume on its own.
    public var needsManualResume = false

    public init() {}
}

public struct AudioInput: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum CaptureEvent: Sendable {
    case progress(recorded: TimeInterval, level: Float)
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case failed(String)
}

public enum MicrophoneAccess: Sendable {
    case undetermined, granted, denied
}
