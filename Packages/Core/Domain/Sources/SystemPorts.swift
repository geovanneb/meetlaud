import Foundation

/// Decides when the app is locked and covered. Face ID itself makes the app inactive, which would otherwise lock it
/// again the moment it unlocks, and prompt forever after a cancel. So only the background locks.
public struct AppLockState: Equatable, Sendable {
    public private(set) var isEnabled: Bool
    public private(set) var isLocked: Bool
    /// The app switcher takes its picture on the way out, so the content has to be gone before that.
    public private(set) var isCovered: Bool
    private var isAuthenticating = false
    private var hasPrompted = false

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
        isLocked = isEnabled
        isCovered = isEnabled
    }

    public mutating func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            isLocked = false
            isCovered = false
        }
    }

    public mutating func becameInactive() {
        isCovered = isEnabled
    }

    public mutating func enteredBackground() {
        guard isEnabled else { return }
        isLocked = true
        isCovered = true
        hasPrompted = false
    }

    /// Returns whether to ask for Face ID now. Asks once, and after a cancel the Unlock button asks again.
    public mutating func becameActive() -> Bool {
        guard isLocked else {
            isCovered = false
            return false
        }
        guard !isAuthenticating, !hasPrompted else { return false }
        hasPrompted = true
        isAuthenticating = true
        return true
    }

    /// For the Unlock button. Returns false while a prompt is already up.
    public mutating func requestUnlock() -> Bool {
        guard isLocked, !isAuthenticating else { return false }
        isAuthenticating = true
        return true
    }

    public mutating func finishAuthentication(success: Bool) {
        isAuthenticating = false
        if success {
            isLocked = false
            isCovered = false
        }
    }
}

public enum AppLockPreferences {
    public static let enabledKey = "privacy.appLock"
}

public protocol DeviceAuthenticator: Sendable {
    /// False when the device has no passcode, in which case a lock could never be opened again.
    var isAvailable: Bool { get }
    func authenticate(reason: String) async -> Bool
}

public enum NotificationPreferences {
    public static let transcriptReadyKey = "notifications.transcriptReady"
    public static let eventRemindersKey = "notifications.eventReminders"
    /// Minutes before a meeting.
    public static let reminderLead: TimeInterval = 10 * 60
}

public protocol LocalNotifier: Sendable {
    func requestAccess() async -> Bool
    func notify(id: String, title: String, body: String) async
    /// Replaces every reminder set earlier.
    func scheduleReminders(for events: [CalendarEvent], title: String) async
}

public struct StorageUsage: Hashable, Sendable {
    public let recordings: Int64
    public let library: Int64
    public let models: Int64
    public let cache: Int64

    public init(recordings: Int64, library: Int64, models: Int64, cache: Int64) {
        self.recordings = recordings
        self.library = library
        self.models = models
        self.cache = cache
    }

    public var total: Int64 {
        recordings + library + models + cache
    }
}

public enum StoragePreferences {
    public static let backupIncludedKey = "storage.backupIncluded"
}

public protocol StorageManaging: Sendable {
    func usage() -> StorageUsage
    func clearCache()
    /// Models stay out either way: they can be downloaded again, and they are huge.
    func setBackupIncluded(_ included: Bool) throws
    /// Removes every recording, attachment, and leftover file. The database is the store's job.
    func removeEverything() throws
}

public enum ArchiveError: Error, Equatable {
    case wrongPassword
    case damaged
    /// Made by a newer version of the app.
    case incompatible
}

/// Copies the database out and back in. Lives next to the database, since nothing else may touch it.
public protocol DatabaseSnapshots: Sendable {
    func writeSnapshot(to url: URL, includingVoicePrints: Bool) async throws
    /// Replaces everything in the live database. Throws before changing anything if it cannot be read.
    func restoreSnapshot(from url: URL) async throws
    func eraseEverything() async throws
}

public protocol LibraryArchiver: Sendable {
    func export(
        to url: URL,
        password: String,
        includingVoicePrints: Bool,
        progress: @escaping @Sendable (Double) -> Void,
    ) async throws
    /// Replaces the library with the archive's. Nothing changes unless the whole file reads correctly.
    func restore(from url: URL, password: String, progress: @escaping @Sendable (Double) -> Void) async throws
}
