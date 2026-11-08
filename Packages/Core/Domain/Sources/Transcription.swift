import Foundation

public struct TranscriptSegment: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let recordingID: RecordingID
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var speaker: String?

    public init(
        id: UUID = UUID(),
        recordingID: RecordingID,
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        speaker: String? = nil,
    ) {
        self.id = id
        self.recordingID = recordingID
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
    }
}

public struct Transcript: Hashable, Sendable {
    public let recordingID: RecordingID
    public var modelID: String
    public var language: String?
    public var isComplete: Bool

    public init(recordingID: RecordingID, modelID: String, language: String?, isComplete: Bool) {
        self.recordingID = recordingID
        self.modelID = modelID
        self.language = language
        self.isComplete = isComplete
    }
}

public enum JobState: String, Sendable {
    case queued, running, paused
    /// The person chose to start it once the device is on a charger.
    case waitingForPower
}

/// Work that survives the app closing. `checkpoint` is the audio position already saved.
public struct TranscriptionJob: Hashable, Sendable {
    public let recordingID: RecordingID
    public let modelID: String
    public var language: String?
    public var checkpoint: TimeInterval
    public var state: JobState

    public init(
        recordingID: RecordingID,
        modelID: String,
        language: String?,
        checkpoint: TimeInterval = 0,
        state: JobState = .queued,
    ) {
        self.recordingID = recordingID
        self.modelID = modelID
        self.language = language
        self.checkpoint = checkpoint
        self.state = state
    }
}

/// A stretch of audio, already at 16 kHz mono, small enough to hold in memory.
public struct AudioWindow: Sendable {
    public let start: TimeInterval
    public let end: TimeInterval
    public let samples: [Float]

    public init(start: TimeInterval, end: TimeInterval, samples: [Float]) {
        self.start = start
        self.end = end
        self.samples = samples
    }
}

/// A piece of speech. Times are relative to the window it came from.
public struct SpeechSegment: Hashable, Sendable {
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct WindowResult: Sendable {
    public let segments: [SpeechSegment]
    public let language: String?

    public init(segments: [SpeechSegment], language: String?) {
        self.segments = segments
        self.language = language
    }
}

public enum TranscriptionError: Error, Equatable {
    case modelNotInstalled
    case missingModelFiles
    case languageNotSupported
    case audioUnavailable
}

/// Turns speech into text. Every engine in the app sits behind this, and passes the same contract tests.
public protocol TranscriptionEngine: ModelRunner {
    func transcribe(_ window: AudioWindow, language: String?) async throws -> WindowResult
}

/// Reads a file as a sequence of windows, so that memory stays flat however long the meeting is.
public protocol AudioWindowSource: Sendable {
    func duration(of file: URL) async throws -> TimeInterval
    func windows(of file: URL, from start: TimeInterval) -> AsyncThrowingStream<AudioWindow, any Error>
}

/// A transcript that was replaced. Changing models must never cost someone text they already had.
public struct TranscriptVersion: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let recordingID: RecordingID
    public let modelID: String
    public let language: String?
    public let savedAt: Date
    public let segments: [TranscriptSegment]

    /// Older ones go first. A meeting can hold a lot of text, and this is a safety net and not an archive.
    public static let limit = 3

    public init(
        id: UUID = UUID(),
        recordingID: RecordingID,
        modelID: String,
        language: String?,
        savedAt: Date,
        segments: [TranscriptSegment],
    ) {
        self.id = id
        self.recordingID = recordingID
        self.modelID = modelID
        self.language = language
        self.savedAt = savedAt
        self.segments = segments
    }
}

public protocol TranscriptStore: Sendable {
    /// Newest first.
    func versions(for id: RecordingID) async throws -> [TranscriptVersion]
    /// Keeps only the newest `TranscriptVersion.limit`.
    func save(_ version: TranscriptVersion) async throws
    func deleteVersion(_ id: UUID) async throws
    func transcript(for id: RecordingID) async throws -> Transcript?
    func save(_ transcript: Transcript) async throws
    func segments(for id: RecordingID) async throws -> [TranscriptSegment]
    /// Saves a window's text and its checkpoint in one transaction, so that a crash can never repeat or lose text.
    func append(_ segments: [TranscriptSegment], job: TranscriptionJob) async throws
    func update(_ segment: TranscriptSegment) async throws
    /// Covers phrases and speaker names. Returns how many changed.
    func replaceAll(in id: RecordingID, of text: String, with replacement: String) async throws -> Int
    func deleteTranscript(for id: RecordingID) async throws

    func job(for id: RecordingID) async throws -> TranscriptionJob?
    func jobs() async throws -> [TranscriptionJob]
    func save(_ job: TranscriptionJob) async throws
    func deleteJob(for id: RecordingID) async throws
}

/// Lets long work continue when the user leaves the app, where iOS allows it.
public protocol BackgroundWorkLease: Sendable {
    func begin(title: String) async
    func update(progress: Double) async
    func end() async
}

public struct JobProgress: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        case queued, preparing, transcribing, separatingSpeakers, waitingForDevice, waitingForPower
    }

    public let phase: Phase
    /// From 0 to 1.
    public let fraction: Double

    public init(phase: Phase, fraction: Double) {
        self.phase = phase
        self.fraction = fraction
    }
}
