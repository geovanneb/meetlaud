import Foundation

public enum MarkerKind: String, Sendable, Codable {
    case flag, note, photo
}

/// A moment the user marked while recording. `time` is position in the audio, which excludes pauses.
public struct Marker: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let recordingID: RecordingID
    public let time: TimeInterval
    public let kind: MarkerKind
    public var text: String?
    /// File name inside the recording's attachments folder.
    public var attachment: String?

    public init(
        id: UUID = UUID(),
        recordingID: RecordingID,
        time: TimeInterval,
        kind: MarkerKind,
        text: String? = nil,
        attachment: String? = nil,
    ) {
        self.id = id
        self.recordingID = recordingID
        self.time = time
        self.kind = kind
        self.text = text
        self.attachment = attachment
    }
}

public enum PauseReason: String, Sendable, Codable {
    case user, interruption
}

/// A gap in a recording, so the timeline can show that time passed here.
public struct PauseSpan: Hashable, Sendable {
    public let recordingID: RecordingID
    public let position: TimeInterval
    public let duration: TimeInterval
    public let reason: PauseReason

    public init(recordingID: RecordingID, position: TimeInterval, duration: TimeInterval, reason: PauseReason) {
        self.recordingID = recordingID
        self.position = position
        self.duration = duration
        self.reason = reason
    }
}
