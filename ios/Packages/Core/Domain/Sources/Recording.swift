import Foundation

/// Stable identity of a recording. A dedicated type prevents mixing it with other UUIDs.
public struct RecordingID: Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    /// Fails for anything that is not a valid UUID, such as untrusted deep link input.
    public init?(string: String) {
        guard let uuid = UUID(uuidString: string) else { return nil }
        rawValue = uuid
    }
}

public enum RecordingStatus: String, Sendable, Codable {
    /// Audio is being written, or the app died while writing it. Recovery looks for this state.
    case capturing
    /// The final audio file exists.
    case ready
}

/// The center of the product. Everything else in the domain relates to a recording.
public struct Recording: Identifiable, Hashable, Sendable {
    public let id: RecordingID
    public var title: String
    public let createdAt: Date
    public var duration: TimeInterval
    public var status: RecordingStatus
    /// True when the app rebuilt this recording after a crash.
    public var wasRecovered: Bool
    /// Nil means the main Recordings list.
    public var folderID: FolderID?
    /// When set, the recording is in the trash.
    public var deletedAt: Date?
    public var attendees: [String]

    public init(
        id: RecordingID = RecordingID(),
        title: String,
        createdAt: Date,
        duration: TimeInterval = 0,
        status: RecordingStatus = .ready,
        wasRecovered: Bool = false,
        folderID: FolderID? = nil,
        deletedAt: Date? = nil,
        attendees: [String] = [],
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = max(0, duration)
        self.status = status
        self.wasRecovered = wasRecovered
        self.folderID = folderID
        self.deletedAt = deletedAt
        self.attendees = attendees
    }
}
