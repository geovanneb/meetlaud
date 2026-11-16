import Domain
import Foundation
import Observation

/// Storage, moving the library, and erasing it. The app decides how to stop its own work, through these closures.
@MainActor
@Observable
public final class SystemController {
    public enum ArchiveOutcome: Equatable {
        case idle, working(Double), exported(URL), restored, failed(ArchiveFailureReason)
    }

    public enum ArchiveFailureReason: Equatable {
        case recording, wrongPassword, damaged, incompatible, other
    }

    public private(set) var usage: StorageUsage?
    public private(set) var isBackupIncluded: Bool
    public private(set) var archive = ArchiveOutcome.idle
    public private(set) var isErasing = false

    @ObservationIgnored private let storage: any StorageManaging
    @ObservationIgnored private let archiver: any LibraryArchiver
    @ObservationIgnored private let notifier: any LocalNotifier
    @ObservationIgnored private var pause: @MainActor () async -> Bool = { false }
    @ObservationIgnored private var resume: @MainActor () async -> Void = {}
    @ObservationIgnored private var erase: @MainActor () async throws -> Void = {}

    public init(
        storage: any StorageManaging,
        archiver: any LibraryArchiver,
        notifier: any LocalNotifier,
    ) {
        self.storage = storage
        self.archiver = archiver
        self.notifier = notifier
        isBackupIncluded = UserDefaults.standard.bool(forKey: StoragePreferences.backupIncludedKey)
    }

    /// Set once the app is built, since these reach back into it.
    public func connect(
        pauseAllWork: @escaping @MainActor () async -> Bool,
        resumeAllWork: @escaping @MainActor () async -> Void,
        eraseEverything: @escaping @MainActor () async throws -> Void,
    ) {
        pause = pauseAllWork
        resume = resumeAllWork
        erase = eraseEverything
    }

    func refreshUsage() {
        let storage = storage
        Task.detached { [weak self] in
            let usage = storage.usage()
            await self?.setUsage(usage)
        }
    }

    private func setUsage(_ usage: StorageUsage) {
        self.usage = usage
    }

    func clearCache() {
        storage.clearCache()
        refreshUsage()
    }

    func setBackupIncluded(_ included: Bool) {
        guard (try? storage.setBackupIncluded(included)) != nil else { return }
        isBackupIncluded = included
        UserDefaults.standard.set(included, forKey: StoragePreferences.backupIncludedKey)
    }

    func requestNotificationAccess() async -> Bool {
        await notifier.requestAccess()
    }

    func resetArchive() {
        if case let .exported(url) = archive {
            try? FileManager.default.removeItem(at: url)
        }
        archive = .idle
    }

    func exportLibrary(password: String, includingVoicePrints: Bool) async {
        guard await pause() else {
            archive = .failed(.recording)
            return
        }
        archive = .working(0)
        let url = FileManager.default.temporaryDirectory.appending(path: ExportFileName.safe(
            "Library \(Date().formatted(.iso8601.year().month().day()))", fileExtension: "meetlaudbackup",
        ))
        do {
            try await archiver.export(
                to: url, password: password, includingVoicePrints: includingVoicePrints, progress: report,
            )
            archive = .exported(url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            archive = .failed(.other)
        }
        await resume()
    }

    func restoreLibrary(from url: URL, password: String) async {
        guard await pause() else {
            archive = .failed(.recording)
            return
        }
        archive = .working(0)
        let access = url.startAccessingSecurityScopedResource()
        do {
            try await archiver.restore(from: url, password: password, progress: report)
            archive = .restored
        } catch ArchiveError.wrongPassword {
            archive = .failed(.wrongPassword)
        } catch ArchiveError.incompatible {
            archive = .failed(.incompatible)
        } catch ArchiveError.damaged {
            archive = .failed(.damaged)
        } catch {
            archive = .failed(.other)
        }
        if access {
            url.stopAccessingSecurityScopedResource()
        }
        await resume()
    }

    private nonisolated var report: @Sendable (Double) -> Void {
        { [weak self] fraction in
            Task { @MainActor in self?.setProgress(fraction) }
        }
    }

    private func setProgress(_ fraction: Double) {
        if case .working = archive {
            archive = .working(fraction)
        }
    }

    /// Returns false when it could not run, which only happens during a recording.
    func eraseEverything() async -> Bool {
        isErasing = true
        defer { isErasing = false }
        guard await pause() else { return false }
        let succeeded = await (try? erase()) != nil
        await resume()
        return succeeded
    }
}
