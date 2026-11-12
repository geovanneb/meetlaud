import Domain
import Foundation

public actor FakeTranscriptStore: TranscriptStore, ModelUsageStore {
    private var allVersions: [TranscriptVersion] = []
    private var transcripts: [RecordingID: Transcript] = [:]
    private var allSegments: [TranscriptSegment] = []
    private var allJobs: [RecordingID: TranscriptionJob] = [:]
    private var order: [RecordingID] = []
    private var selections: [ModelRole: SelectionMode] = [:]
    public private(set) var allStats: [ModelRunStat] = []
    private var log: [NetworkLogEntry] = []
    /// Simulates the app dying while saving.
    public var failOnAppend = false

    public init() {}

    public func setFailOnAppend(_ value: Bool) {
        failOnAppend = value
    }

    public func versions(for id: RecordingID) -> [TranscriptVersion] {
        allVersions.filter { $0.recordingID == id }.sorted { $0.savedAt > $1.savedAt }
    }

    public func save(_ version: TranscriptVersion) {
        allVersions.append(version)
        let kept = versions(for: version.recordingID).prefix(TranscriptVersion.limit).map(\.id)
        allVersions.removeAll { $0.recordingID == version.recordingID && !kept.contains($0.id) }
    }

    public func deleteVersion(_ id: UUID) {
        allVersions.removeAll { $0.id == id }
    }

    public func transcript(for id: RecordingID) -> Transcript? {
        transcripts[id]
    }

    public func save(_ transcript: Transcript) {
        transcripts[transcript.recordingID] = transcript
    }

    public func segments(for id: RecordingID) -> [TranscriptSegment] {
        allSegments.filter { $0.recordingID == id }.sorted { $0.start < $1.start }
    }

    public func append(_ segments: [TranscriptSegment], job: TranscriptionJob) throws {
        if failOnAppend {
            throw CancellationError()
        }
        allSegments.append(contentsOf: segments)
        allJobs[job.recordingID] = job
    }

    public func update(_ segment: TranscriptSegment) {
        if let index = allSegments.firstIndex(where: { $0.id == segment.id }) {
            allSegments[index] = segment
        }
    }

    public func replaceAll(in id: RecordingID, of text: String, with replacement: String) -> Int {
        var count = 0
        // Speakers live elsewhere in tests, so only phrases count here.
        for index in allSegments.indices where allSegments[index].recordingID == id {
            let updated = allSegments[index].text.replacing(text, with: replacement)
            if updated != allSegments[index].text {
                allSegments[index].text = updated
                count += 1
            }
        }
        return count
    }

    public func deleteTranscript(for id: RecordingID) {
        allSegments.removeAll { $0.recordingID == id }
        transcripts[id] = nil
    }

    public func job(for id: RecordingID) -> TranscriptionJob? {
        allJobs[id]
    }

    public func jobs() -> [TranscriptionJob] {
        order.compactMap { allJobs[$0] }
    }

    public func save(_ job: TranscriptionJob) {
        if !order.contains(job.recordingID) {
            order.append(job.recordingID)
        }
        allJobs[job.recordingID] = job
    }

    public func deleteJob(for id: RecordingID) {
        allJobs[id] = nil
        order.removeAll { $0 == id }
    }

    public func selection(for role: ModelRole) -> SelectionMode {
        selections[role] ?? .automatic
    }

    public func setSelection(_ mode: SelectionMode, for role: ModelRole) {
        selections[role] = mode
    }

    public func insert(_ stat: ModelRunStat) {
        allStats.append(stat)
    }

    public func stats() -> [ModelRunStat] {
        allStats
    }

    public func logNetwork(_ entry: NetworkLogEntry) {
        log.append(entry)
    }

    public func networkLog() -> [NetworkLogEntry] {
        log
    }

    public func clearNetworkLog() {
        log.removeAll()
    }
}

public final class FakeWindowSource: AudioWindowSource, @unchecked Sendable {
    public var windowLength: TimeInterval = 180
    public var totalDuration: TimeInterval
    /// Stops the windows here, as a file cut short or a stream that ended too soon.
    public var endsAt: TimeInterval?
    private let lock = NSLock()
    private var starts: [TimeInterval] = []

    public init(duration: TimeInterval) {
        totalDuration = duration
    }

    public var requestedStarts: [TimeInterval] {
        lock.withLock { starts }
    }

    public func duration(of _: URL) async throws -> TimeInterval {
        totalDuration
    }

    public func windows(of _: URL, from start: TimeInterval) -> AsyncThrowingStream<AudioWindow, any Error> {
        lock.withLock { starts.append(start) }
        let total = endsAt ?? totalDuration
        let length = windowLength
        return AsyncThrowingStream { continuation in
            var position = start
            while position < total {
                let end = min(position + length, total)
                continuation.yield(AudioWindow(start: position, end: end, samples: []))
                position = end
            }
            continuation.finish()
        }
    }
}

public actor FakeTranscriptionEngine: TranscriptionEngine {
    public private(set) var prepared: [String] = []
    public private(set) var windows: [TimeInterval] = []
    public private(set) var hints: [[String]] = []
    public private(set) var unloads = 0
    public var prepareError: (any Error)?
    /// Fails from this window on.
    public var failAfter: Int?
    /// The next this many calls fail the way a real engine does, as when iOS refuses the hardware.
    public var failures = 0
    /// How long loading and each window take, so a screen can be seen while work runs.
    private let delay: Duration

    public init(delay: Duration = .zero) {
        self.delay = delay
    }

    public func setFailAfter(_ value: Int?) {
        failAfter = value
    }

    public func setFailures(_ value: Int) {
        failures = value
    }

    public func prepare(model: ModelDescriptor, folder _: URL?) async throws {
        if let prepareError {
            throw prepareError
        }
        try await Task.sleep(for: delay)
        prepared.append(model.id)
    }

    public func transcribe(
        _ window: AudioWindow,
        language: String?,
        hints: [String],
        progress: @escaping @Sendable (Double) -> Void,
    ) async throws -> WindowResult {
        if let failAfter, windows.count >= failAfter {
            throw CancellationError()
        }
        if failures > 0 {
            failures -= 1
            throw TranscriptionError.engineFailed
        }
        try await Task.sleep(for: delay)
        progress(0.5)
        windows.append(window.start)
        self.hints.append(hints)
        return WindowResult(
            segments: [
                SpeechSegment(start: 1, end: 2, text: "  Text at \(Int(window.start))  "),
                SpeechSegment(start: 2, end: 3, text: "   "),
            ],
            language: language ?? "pt",
        )
    }

    public func unload() {
        unloads += 1
    }
}

public final class FakeDeviceMonitor: DeviceMonitor, @unchecked Sendable {
    public let changes: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let lock = NSLock()
    private var current: DeviceCondition
    public var deviceProfile: DeviceProfile

    public init(
        profile: DeviceProfile = DeviceProfile(name: "iPhone", identifier: "iPhone18,3", physicalMemoryMB: 8000),
        condition: DeviceCondition = DeviceCondition(),
    ) {
        deviceProfile = profile
        current = condition
        (changes, continuation) = AsyncStream.makeStream()
    }

    public func profile() async -> DeviceProfile {
        deviceProfile
    }

    public func condition() async -> DeviceCondition {
        lock.withLock { current }
    }

    public func setCondition(_ condition: DeviceCondition) {
        lock.withLock { current = condition }
        continuation.yield()
    }
}

public actor FakeLease: BackgroundWorkLease {
    public private(set) var log: [String] = []

    public init() {}

    public func begin(title: String) {
        log.append("begin \(title)")
    }

    public func update(progress _: Double) {}

    public func end() {
        log.append("end")
    }
}

public struct FakeCatalog: ModelCatalog {
    public let models: [ModelDescriptor]

    public init() {
        models = [
            ModelDescriptor(
                id: "fake-small", displayName: "Fast Model", roles: [.transcription], runtime: .whisperKit,
                languages: ["en", "ja", "pt", "es"], quality: ["en": 3],
            ),
            ModelDescriptor(
                id: "fake-large", displayName: "Large Model", roles: [.transcription], runtime: .whisperKit,
                languages: ["en", "ja", "pt", "es"], minMemoryMB: 1000, quality: ["en": 4],
            ),
            ModelDescriptor(
                id: "fake-chat", displayName: "Chat Model", roles: [.chat], runtime: .mlx,
                languages: ["en", "ja", "pt", "es"], quality: ["en": 3],
            ),
            ModelDescriptor(
                id: "fake-search", displayName: "Search Model", roles: [.search], runtime: .appleLanguage,
                languages: ["en", "ja", "pt", "es"], quality: ["en": 3],
            ),
            ModelDescriptor(
                id: "fake-voices", displayName: "Voices", roles: [.speakerSeparation, .voicePrint],
                runtime: .fluidAudio, languages: [],
            ),
        ]
    }
}

public actor FakeInstaller: ModelInstaller {
    public nonisolated let events: AsyncStream<(id: String, state: InstallState)>
    private let continuation: AsyncStream<(id: String, state: InstallState)>.Continuation
    private var installed: Set<String>
    /// Every install asked for, in order.
    public private(set) var installs: [String] = []

    /// The voice model is small enough that tests can treat it as already there.
    public init(installed: Set<String> = ["fake-voices"]) {
        self.installed = installed
        (events, continuation) = AsyncStream.makeStream()
    }

    public func state(of id: String) -> InstallState {
        installed.contains(id) ? .ready : .notInstalled
    }

    public func installedIDs() -> Set<String> {
        installed
    }

    public func install(_ model: ModelDescriptor, allowsCellular _: Bool) {
        installs.append(model.id)
        continuation.yield((model.id, .downloading(received: 50, total: 100)))
        installed.insert(model.id)
        continuation.yield((model.id, .ready))
    }

    public func pause(_ id: String) {
        continuation.yield((id, .paused(received: 50, total: 100)))
    }

    public func cancel(_ id: String) {
        continuation.yield((id, .notInstalled))
    }

    public func remove(_ id: String) {
        installed.remove(id)
        continuation.yield((id, .notInstalled))
    }

    public nonisolated func folder(for _: String) -> URL? {
        nil
    }

    public func reconnect() {}
}

public struct FakeSpeechAssets: SystemSpeechAssets {
    public init() {}

    public func isInstalled(language _: String) async -> Bool {
        false
    }

    public func install(language _: String) async throws {}
}
