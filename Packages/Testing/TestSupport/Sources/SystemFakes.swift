import Domain
import Foundation

public struct FakeAuthenticator: DeviceAuthenticator {
    public let isAvailable: Bool
    private let succeeds: Bool
    /// Real Face ID takes a moment, and that moment is when a person sees the lock.
    private let delay: Duration

    public init(isAvailable: Bool = true, succeeds: Bool = true, delay: Duration = .zero) {
        self.isAvailable = isAvailable
        self.succeeds = succeeds
        self.delay = delay
    }

    public func authenticate(reason _: String) async -> Bool {
        try? await Task.sleep(for: delay)
        return succeeds
    }
}

public actor FakeNotifier: LocalNotifier {
    public private(set) var sent: [String] = []

    public init() {}

    public func requestAccess() -> Bool {
        true
    }

    public func notify(id _: String, title: String, body _: String) {
        sent.append(title)
    }

    public func scheduleReminders(for _: [CalendarEvent], title _: String) {}
}

public final class FakeStorage: StorageManaging, @unchecked Sendable {
    // Unchecked because the lock guards every access.
    private let lock = NSLock()
    private var included = false

    public init() {}

    public var isBackupIncluded: Bool {
        lock.withLock { included }
    }

    public func usage() -> StorageUsage {
        StorageUsage(recordings: 120_000_000, library: 4_000_000, models: 1_500_000_000, cache: 2_000_000)
    }

    public func clearCache() {}

    public func setBackupIncluded(_ included: Bool) {
        lock.withLock { self.included = included }
    }

    public func removeEverything() {}
}

/// Empties a store for real, so that a UI test can see the library go.
public struct FakeDatabaseSnapshots: DatabaseSnapshots {
    private let store: any RecordingStore

    public init(store: any RecordingStore) {
        self.store = store
    }

    public func writeSnapshot(to _: URL, includingVoicePrints _: Bool) {}

    public func restoreSnapshot(from _: URL) {}

    public func eraseEverything() async throws {
        for status in [RecordingStatus.ready, .capturing] {
            for recording in try await store.recordings(status: status) {
                try await store.delete(recording.id)
            }
        }
    }
}

public struct FakeArchiver: LibraryArchiver {
    public init() {}

    public func export(
        to url: URL,
        password _: String,
        includingVoicePrints _: Bool,
        progress: @escaping @Sendable (Double) -> Void,
    ) throws {
        try Data("archive".utf8).write(to: url)
        progress(1)
    }

    public func restore(from _: URL, password: String, progress: @escaping @Sendable (Double) -> Void) throws {
        guard password == "correct horse" else { throw ArchiveError.wrongPassword }
        progress(1)
    }
}
