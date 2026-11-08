import Foundation

public struct FolderID: Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init?(string: String) {
        guard let uuid = UUID(uuidString: string) else { return nil }
        rawValue = uuid
    }
}

public struct Folder: Identifiable, Hashable, Sendable {
    public let id: FolderID
    public var name: String
    public let createdAt: Date

    public init(id: FolderID = FolderID(), name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

public enum RecordingSort: String, CaseIterable, Sendable {
    case newest, oldest, name, longest

    public func sorted(_ recordings: [Recording]) -> [Recording] {
        switch self {
        case .newest:
            recordings.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            recordings.sorted { $0.createdAt < $1.createdAt }
        case .name:
            recordings.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .longest:
            recordings.sorted { $0.duration > $1.duration }
        }
    }
}

/// A place in a recording that matches a search. `time` is nil when the match is the recording itself.
public struct SearchHit: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let recording: Recording
    public let time: TimeInterval?
    public let excerpt: String?

    public init(id: UUID = UUID(), recording: Recording, time: TimeInterval? = nil, excerpt: String? = nil) {
        self.id = id
        self.recording = recording
        self.time = time
        self.excerpt = excerpt
    }
}

public struct CalendarEvent: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let attendees: [String]

    public init(id: String, title: String, start: Date, end: Date, attendees: [String]) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.attendees = attendees
    }
}

public extension CalendarEvent {
    /// Whether the event says anything. Busy blocks from shared calendars arrive with no title and no people, and
    /// there is nothing to show or to record about them.
    var hasDetails: Bool {
        hasTitle || !attendees.isEmpty
    }

    var hasTitle: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum AppTheme: String, CaseIterable, Sendable {
    case system, light, dark
}

public enum ThemePreferences {
    public static let key = "appearance.theme"
}

public enum WidgetPreferences {
    /// Off by default: a meeting's name on the Home Screen can be seen by anyone holding the phone.
    public static let showContentKey = "widgets.showContent"
}

public enum CalendarAccess: Sendable {
    case undetermined, granted, denied
}
