import Domain
import Foundation

/// Capture engine driven by the test. Also used by UI tests, which have no real microphone.
public final class FakeCaptureEngine: AudioCaptureEngine, @unchecked Sendable {
    public let events: AsyncStream<CaptureEvent>
    private let continuation: AsyncStream<CaptureEvent>.Continuation
    private let lock = NSLock()
    private var _calls: [String] = []
    public var startError: (any Error)?
    public var resumeError: (any Error)?

    public init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    public var calls: [String] {
        lock.withLock { _calls }
    }

    private func log(_ call: String) {
        lock.withLock { _calls.append(call) }
    }

    public func send(_ event: CaptureEvent) {
        continuation.yield(event)
    }

    public func start(directory _: URL) async throws {
        log("start")
        if let startError {
            throw startError
        }
    }

    public func pause() async {
        log("pause")
    }

    public func resume() async throws {
        log("resume")
        if let resumeError {
            throw resumeError
        }
    }

    public func stop() async throws {
        log("stop")
    }

    public func deactivate() async {
        log("deactivate")
    }

    public func availableInputs() async -> [AudioInput] {
        [AudioInput(id: "built-in", name: "iPhone")]
    }

    public func selectInput(_: AudioInput) async throws {}
}

public actor InMemoryRecordingStore: RecordingStore {
    public private(set) var all: [RecordingID: Recording] = [:]
    public private(set) var allMarkers: [Marker] = []
    public private(set) var allPauses: [PauseSpan] = []
    public private(set) var folders: [FolderID: Folder] = [:]
    private var observers: [AsyncStream<[Recording]>.Continuation] = []
    private var folderObservers: [AsyncStream<[Folder]>.Continuation] = []

    public init() {}

    private var sorted: [Recording] {
        all.values.sorted { $0.createdAt > $1.createdAt }
    }

    private func publish() {
        for observer in observers {
            observer.yield(sorted)
        }
    }

    public func insert(_ recording: Recording) {
        all[recording.id] = recording
        publish()
    }

    public func update(_ recording: Recording) {
        all[recording.id] = recording
        publish()
    }

    public func delete(_ id: RecordingID) {
        all[id] = nil
        publish()
    }

    public func recording(_ id: RecordingID) -> Recording? {
        all[id]
    }

    public func recordings(status: RecordingStatus) -> [Recording] {
        sorted.filter { $0.status == status }
    }

    public func insert(_ marker: Marker) {
        allMarkers.append(marker)
    }

    public func markers(for id: RecordingID) -> [Marker] {
        allMarkers.filter { $0.recordingID == id }.sorted { $0.time < $1.time }
    }

    public func insert(_ pause: PauseSpan) {
        allPauses.append(pause)
    }

    public func pauses(for id: RecordingID) -> [PauseSpan] {
        allPauses.filter { $0.recordingID == id }
    }

    public func trashedRecordings() -> [Recording] {
        sorted.filter { $0.deletedAt != nil }
    }

    public func search(_ query: String) -> [SearchHit] {
        let active = sorted.filter { $0.deletedAt == nil }
        let titles = active
            .filter { $0.title.localizedCaseInsensitiveContains(query) }
            .map { SearchHit(recording: $0) }
        let notes = allMarkers.compactMap { marker -> SearchHit? in
            guard
                marker.text?.localizedCaseInsensitiveContains(query) == true,
                let recording = active.first(where: { $0.id == marker.recordingID })
            else { return nil }
            return SearchHit(recording: recording, time: marker.time, excerpt: marker.text)
        }
        return titles + notes
    }

    private var sortedFolders: [Folder] {
        folders.values.sorted { $0.createdAt < $1.createdAt }
    }

    private func publishFolders() {
        for observer in folderObservers {
            observer.yield(sortedFolders)
        }
    }

    public func insert(_ folder: Folder) {
        folders[folder.id] = folder
        publishFolders()
    }

    public func update(_ folder: Folder) {
        folders[folder.id] = folder
        publishFolders()
    }

    public func delete(_ folder: FolderID) {
        folders[folder] = nil
        for (id, recording) in all where recording.folderID == folder {
            all[id]?.folderID = nil
        }
        publishFolders()
        publish()
    }

    private func registerFolders(_ continuation: AsyncStream<[Folder]>.Continuation) {
        folderObservers.append(continuation)
        continuation.yield(sortedFolders)
    }

    public nonisolated func observeFolders() -> AsyncStream<[Folder]> {
        AsyncStream { continuation in
            Task { await self.registerFolders(continuation) }
        }
    }

    private func register(_ continuation: AsyncStream<[Recording]>.Continuation) {
        observers.append(continuation)
        continuation.yield(sorted)
    }

    public nonisolated func observeRecordings() -> AsyncStream<[Recording]> {
        AsyncStream { continuation in
            Task { await self.register(continuation) }
        }
    }
}

public final class FakeRecordingFiles: RecordingFiles, @unchecked Sendable {
    private let lock = NSLock()
    private var segments: Set<RecordingID> = []
    private var _available: Int64 = 10_000_000_000
    private var copiedAttachments = 0
    private var removed: Set<RecordingID> = []

    public init() {}

    public var available: Int64 {
        get { lock.withLock { _available } }
        set { lock.withLock { _available = newValue } }
    }

    public func addSegments(for id: RecordingID) {
        lock.withLock { _ = segments.insert(id) }
    }

    public func segmentsDirectory(for id: RecordingID) throws -> URL {
        lock.withLock { _ = segments.insert(id) }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: id.rawValue.uuidString)
    }

    public func audioFile(for id: RecordingID) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "\(id.rawValue.uuidString).m4a")
    }

    public func attachmentsDirectory(for id: RecordingID) throws -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "attachments-\(id.rawValue.uuidString)")
    }

    public func prepare(for _: RecordingID) throws {}

    public func copyAttachment(_: String, from _: RecordingID, to _: RecordingID) throws {
        lock.withLock { copiedAttachments += 1 }
    }

    public var attachmentsCopied: Int {
        lock.withLock { copiedAttachments }
    }

    public func removeSegments(for id: RecordingID) throws {
        lock.withLock { _ = segments.remove(id) }
    }

    public func removeAll(for id: RecordingID) throws {
        lock.withLock {
            _ = segments.remove(id)
            removed.insert(id)
        }
    }

    public func wasRemoved(_ id: RecordingID) -> Bool {
        lock.withLock { removed.contains(id) }
    }

    public func hasSegments(for id: RecordingID) -> Bool {
        lock.withLock { segments.contains(id) }
    }

    public func availableBytes() -> Int64 {
        available
    }
}

public final class FakeAssembler: AudioAssembler, @unchecked Sendable {
    public var duration: TimeInterval
    public var error: (any Error)?

    public init(duration: TimeInterval = 12) {
        self.duration = duration
    }

    public func assemble(segments _: URL, into _: URL) async throws -> TimeInterval {
        if let error {
            throw error
        }
        return duration
    }
}

public final class FakeAudioProcessor: AudioProcessor, @unchecked Sendable {
    public var duration: TimeInterval
    public var error: (any Error)?

    public init(duration: TimeInterval = 30) {
        self.duration = duration
    }

    public func importAudio(from _: URL, to _: URL) async throws -> TimeInterval {
        if let error {
            throw error
        }
        return duration
    }

    public func merge(_ sources: [URL], to _: URL) async throws -> TimeInterval {
        if let error {
            throw error
        }
        return duration * Double(sources.count)
    }
}

public final class FakeCalendarProvider: CalendarProvider, @unchecked Sendable {
    public var access: CalendarAccess
    public var events: [CalendarEvent]
    public var sources: [CalendarSource]

    public init(access: CalendarAccess = .undetermined, events: [CalendarEvent] = [], sources: [CalendarSource] = []) {
        self.access = access
        self.events = events
        self.sources = sources
    }

    public func calendars() async -> [CalendarSource] {
        access == .granted ? sources : []
    }

    public func requestAccess() async -> Bool {
        access = .granted
        return true
    }

    public func events(from start: Date, to end: Date) async -> [CalendarEvent] {
        access == .granted ? events.filter { $0.end >= start && $0.start < end } : []
    }
}

public actor FakeActivityPresenter: RecordingActivityPresenter {
    public private(set) var log: [String] = []

    public init() {}

    public func begin(title: String) {
        log.append("begin \(title)")
    }

    public func update(status: CaptureStatus, recorded _: TimeInterval) {
        log.append("update \(status)")
    }

    public func end() {
        log.append("end")
    }
}

public struct FakeMicrophonePermission: MicrophonePermission {
    public var access: MicrophoneAccess
    public var answer: Bool

    public init(access: MicrophoneAccess = .granted, answer: Bool = true) {
        self.access = access
        self.answer = answer
    }

    public func request() async -> Bool {
        answer
    }
}
