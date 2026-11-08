import Foundation

/// Captures microphone audio into raw segments inside a directory.
public protocol AudioCaptureEngine: Sendable {
    var events: AsyncStream<CaptureEvent> { get }
    func start(directory: URL) async throws
    /// Stops writing. The microphone stays open, so the app stays alive and can resume from the Lock Screen.
    func pause() async
    func resume() async throws
    /// Closes the audio so that every sample written is on disk.
    func stop() async throws
    /// Releases the audio session. Called after the final file is saved.
    func deactivate() async
    func availableInputs() async -> [AudioInput]
    func selectInput(_ input: AudioInput) async throws
}

/// Turns raw segments into the final audio file.
public protocol AudioAssembler: Sendable {
    /// Returns the duration of the file written. Must not delete the segments.
    func assemble(segments directory: URL, into file: URL) async throws -> TimeInterval
}

public protocol RecordingStore: Sendable {
    func insert(_ recording: Recording) async throws
    func update(_ recording: Recording) async throws
    func delete(_ id: RecordingID) async throws
    func recording(_ id: RecordingID) async throws -> Recording?
    func recordings(status: RecordingStatus) async throws -> [Recording]
    func insert(_ marker: Marker) async throws
    func markers(for id: RecordingID) async throws -> [Marker]
    func insert(_ pause: PauseSpan) async throws
    func pauses(for id: RecordingID) async throws -> [PauseSpan]
    func trashedRecordings() async throws -> [Recording]
    /// Matches titles and notes in recordings that are not in the trash.
    func search(_ query: String) async throws -> [SearchHit]
    /// Emits the full list now and after every change, trash included.
    func observeRecordings() -> AsyncStream<[Recording]>

    func insert(_ folder: Folder) async throws
    func update(_ folder: Folder) async throws
    /// Recordings inside return to the main list.
    func delete(_ folder: FolderID) async throws
    func observeFolders() -> AsyncStream<[Folder]>
}

/// Reads and writes finished audio files, as opposed to capturing them.
public protocol AudioProcessor: Sendable {
    /// Converts any supported audio or video file into the app's audio format. Returns the duration.
    func importAudio(from source: URL, to file: URL) async throws -> TimeInterval
    /// Joins files in order. Returns the total duration. Does not touch the originals.
    func merge(_ sources: [URL], to file: URL) async throws -> TimeInterval
}

public protocol CalendarProvider: Sendable {
    var access: CalendarAccess { get }
    func requestAccess() async -> Bool
    /// Timed events in a period, soonest first. All-day events, cancelled ones, and ones the person declined stay out.
    func events(from start: Date, to end: Date) async -> [CalendarEvent]
}

public protocol RecordingFiles: Sendable {
    func segmentsDirectory(for id: RecordingID) throws -> URL
    func audioFile(for id: RecordingID) -> URL
    func attachmentsDirectory(for id: RecordingID) throws -> URL
    /// Creates the recording's folder, for when audio arrives without segments.
    func prepare(for id: RecordingID) throws
    func copyAttachment(_ name: String, from source: RecordingID, to destination: RecordingID) throws
    func removeSegments(for id: RecordingID) throws
    func removeAll(for id: RecordingID) throws
    func hasSegments(for id: RecordingID) -> Bool
    func availableBytes() -> Int64
}

/// The system surface that shows the recording outside the app.
public protocol RecordingActivityPresenter: Sendable {
    func begin(title: String) async
    func update(status: CaptureStatus, recorded: TimeInterval) async
    func end() async
}

public protocol MicrophonePermission: Sendable {
    var access: MicrophoneAccess { get }
    func request() async -> Bool
}

@MainActor
public protocol AudioPlaying: AnyObject {
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get }
    var isPlaying: Bool { get }
    var rate: Float { get set }
    func load(_ file: URL, title: String) throws
    func play()
    func pause()
    func seek(to time: TimeInterval)
    func stop()
}

public protocol ModelCatalog: Sendable {
    var models: [ModelDescriptor] { get }
}

/// Puts model files on the device. This is the only way anything in the app reaches the network.
public protocol ModelInstaller: Sendable {
    var events: AsyncStream<(id: String, state: InstallState)> { get }
    func state(of id: String) async -> InstallState
    func installedIDs() async -> Set<String>
    func install(_ model: ModelDescriptor, allowsCellular: Bool) async
    func pause(_ id: String) async
    func cancel(_ id: String) async
    func remove(_ id: String) async throws
    func folder(for id: String) -> URL?
    /// Reconnects to downloads that continued while the app was closed.
    func reconnect() async
}

public protocol ModelUsageStore: Sendable {
    func selection(for role: ModelRole) async throws -> SelectionMode
    func setSelection(_ mode: SelectionMode, for role: ModelRole) async throws
    func insert(_ stat: ModelRunStat) async throws
    func stats() async throws -> [ModelRunStat]
    func logNetwork(_ entry: NetworkLogEntry) async throws
    func networkLog() async throws -> [NetworkLogEntry]
}

public struct NetworkLogEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let host: String
    public let modelID: String
    public let bytes: Int64
    public let date: Date

    public init(id: UUID = UUID(), host: String, modelID: String, bytes: Int64, date: Date) {
        self.id = id
        self.host = host
        self.modelID = modelID
        self.bytes = bytes
        self.date = date
    }
}

public protocol DeviceMonitor: Sendable {
    func profile() async -> DeviceProfile
    func condition() async -> DeviceCondition
    /// Fires when something relevant changes. There is no polling behind this.
    var changes: AsyncStream<Void> { get }
}
