import CryptoKit
import Domain
import Foundation

/// Downloads models. The only code in the app that touches the network.
///
/// Files land in a staging folder, each is verified, and the whole folder moves into place at the end. Engines
/// can never see a partial model. A background session keeps going when the app closes.
public final class ModelDownloader: NSObject, ModelInstaller, @unchecked Sendable {
    /// Room for Core ML to compile the model, on top of the download.
    static let spaceMargin: Int64 = 300_000_000
    private static let completeMarker = ".complete"
    private static let retriesAfterDamage = 1

    public let events: AsyncStream<(id: String, state: InstallState)>
    private let continuation: AsyncStream<(id: String, state: InstallState)>.Continuation

    private let root: URL
    private let catalog: [String: ModelDescriptor]
    private let freeBytes: @Sendable () -> Int64
    private let log: @Sendable (NetworkLogEntry) -> Void
    private let lock = NSLock()
    private let queue: OperationQueue

    private var session: URLSession!
    private var states: [String: InstallState] = [:]
    private var inFlight: [Int: Int64] = [:]
    private var damageRetries: [String: Int] = [:]
    private var pausing: Set<String> = []
    /// Models being verified and moved. Each file's task checks "all staged?" when it completes, and with several
    /// files more than one can see yes before the first finish has moved the folder. A second finish would then
    /// find no staging folder and report a failure over a good install.
    private var finishing: Set<String> = []
    private var backgroundCompletion: (@Sendable () -> Void)?

    public init(
        root: URL,
        catalog: [ModelDescriptor],
        configuration: URLSessionConfiguration = ModelDownloader.backgroundConfiguration(),
        freeBytes: @escaping @Sendable () -> Int64,
        log: @escaping @Sendable (NetworkLogEntry) -> Void,
    ) throws {
        self.root = root
        self.catalog = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        self.freeBytes = freeBytes
        self.log = log
        (events, continuation) = AsyncStream.makeStream()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        super.init()
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        var folder = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    public static func backgroundConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.meetlaud.app.models")
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.httpMaximumConnectionsPerHost = 3
        return configuration
    }

    /// iOS wakes the app when background downloads end. Call this from the app delegate.
    public func handleBackgroundEvents(completion: @escaping @Sendable () -> Void) {
        lock.withLock { backgroundCompletion = completion }
    }

    private var stagingRoot: URL {
        root.appending(path: ".staging")
    }

    private func staging(_ id: String) -> URL {
        stagingRoot.appending(path: id)
    }

    private func installed(_ id: String) -> URL {
        root.appending(path: id)
    }

    // MARK: - ModelInstaller

    public func folder(for id: String) -> URL? {
        let url = installed(id)
        let marker = url.appending(path: Self.completeMarker)
        return FileManager.default.fileExists(atPath: marker.path) ? url : nil
    }

    public func installedIDs() async -> Set<String> {
        Set(catalog.keys.filter { folder(for: $0) != nil })
    }

    public func state(of id: String) async -> InstallState {
        if folder(for: id) != nil {
            return .ready
        }
        return lock.withLock { states[id] } ?? .notInstalled
    }

    public func install(_ model: ModelDescriptor, allowsCellular: Bool) async {
        guard folder(for: model.id) == nil else {
            update(model.id, .ready)
            return
        }
        guard freeBytes() >= model.totalBytes + Self.spaceMargin else {
            update(model.id, .failed(.noSpace))
            return
        }
        do {
            try FileManager.default.createDirectory(at: staging(model.id), withIntermediateDirectories: true)
        } catch {
            update(model.id, .failed(.unavailable))
            return
        }
        update(model.id, .queued)

        let running = await session.allTasks.filter { Self.identity(of: $0)?.id == model.id }
        let active = Set(running.compactMap { Self.identity(of: $0)?.path })
        let missing = model.files.filter { !isStaged($0, in: model.id) && !active.contains($0.path) }
        if missing.isEmpty, active.isEmpty {
            finish(model)
            return
        }
        for file in missing {
            start(file, of: model, allowsCellular: allowsCellular)
        }
    }

    private func start(_ file: ModelFile, of model: ModelDescriptor, allowsCellular: Bool = false) {
        let resumeFile = resumeURL(for: file, in: model.id)
        let task: URLSessionDownloadTask
        if let data = try? Data(contentsOf: resumeFile) {
            task = session.downloadTask(withResumeData: data)
            try? FileManager.default.removeItem(at: resumeFile)
        } else {
            var request = URLRequest(url: file.url)
            request.allowsCellularAccess = allowsCellular
            task = session.downloadTask(with: request)
        }
        task.taskDescription = "\(model.id)\n\(file.path)"
        task.resume()
    }

    public func pause(_ id: String) async {
        lock.withLock { _ = pausing.insert(id) }
        for task in await session.allTasks where Self.identity(of: task)?.id == id {
            guard let download = task as? URLSessionDownloadTask, let path = Self.identity(of: task)?.path else {
                continue
            }
            let data = await download.cancelByProducingResumeData()
            if let data, let file = catalog[id]?.files.first(where: { $0.path == path }) {
                try? data.write(to: resumeURL(for: file, in: id))
            }
        }
        let received = stagedBytes(id)
        lock.withLock { _ = pausing.remove(id) }
        update(id, .paused(received: received, total: catalog[id]?.totalBytes ?? 0))
    }

    public func cancel(_ id: String) async {
        lock.withLock { _ = pausing.insert(id) }
        for task in await session.allTasks where Self.identity(of: task)?.id == id {
            task.cancel()
        }
        try? FileManager.default.removeItem(at: staging(id))
        lock.withLock { _ = pausing.remove(id) }
        update(id, .notInstalled)
    }

    public func remove(_ id: String) async throws {
        await cancel(id)
        if FileManager.default.fileExists(atPath: installed(id).path) {
            try FileManager.default.removeItem(at: installed(id))
        }
        update(id, .notInstalled)
    }

    public func reconnect() async {
        let tasks = await session.allTasks
        let running = Set(tasks.compactMap { Self.identity(of: $0)?.id })
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: stagingRoot.path)) ?? []
        for id in folders where catalog[id] != nil {
            let received = stagedBytes(id)
            let total = catalog[id]?.totalBytes ?? 0
            if running.contains(id) {
                update(id, .downloading(received: received, total: total))
            } else if let model = catalog[id], model.files.allSatisfy({ isStaged($0, in: id) }) {
                // Every file arrived while the app was closed.
                finish(model)
            } else {
                update(id, .paused(received: received, total: total))
            }
        }
    }

    // MARK: - Finishing

    private func finish(_ model: ModelDescriptor) {
        guard lock.withLock({ finishing.insert(model.id).inserted }) else { return }
        update(model.id, .verifying)
        Task.detached(priority: .utility) { [self] in
            defer { lock.withLock { _ = finishing.remove(model.id) } }
            do {
                try verify(model)
                try FileManager.default.moveItem(at: staging(model.id), to: installed(model.id))
                FileManager.default.createFile(
                    atPath: installed(model.id).appending(path: Self.completeMarker).path,
                    contents: nil,
                )
                log(NetworkLogEntry(host: model.sourceHost, modelID: model.id, bytes: model.totalBytes, date: Date()))
                update(model.id, .ready)
            } catch let VerificationError.damaged(file) {
                handleDamage(model, file: file)
            } catch {
                update(model.id, .failed(.unavailable))
            }
        }
    }

    private enum VerificationError: Error {
        case damaged(ModelFile)
    }

    private func verify(_ model: ModelDescriptor) throws {
        for file in model.files {
            let url = staging(model.id).appending(path: file.path)
            guard try Self.sha256(of: url) == file.sha256 else { throw VerificationError.damaged(file) }
        }
    }

    private func handleDamage(_ model: ModelDescriptor, file: ModelFile) {
        try? FileManager.default.removeItem(at: staging(model.id).appending(path: file.path))
        let retries = lock.withLock {
            damageRetries[model.id, default: 0] += 1
            return damageRetries[model.id, default: 0]
        }
        if retries <= Self.retriesAfterDamage {
            // The retry finishes on its own later, so this finish must let go first.
            lock.withLock { _ = finishing.remove(model.id) }
            start(file, of: model)
        } else {
            lock.withLock { damageRetries[model.id] = 0 }
            try? FileManager.default.removeItem(at: staging(model.id))
            update(model.id, .failed(.damaged))
        }
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Helpers

    private func update(_ id: String, _ state: InstallState) {
        lock.withLock { states[id] = state }
        continuation.yield((id, state))
    }

    private func isStaged(_ file: ModelFile, in id: String) -> Bool {
        let url = staging(id).appending(path: file.path)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? -1
        return size == file.size
    }

    private func stagedBytes(_ id: String) -> Int64 {
        catalog[id]?.files.filter { isStaged($0, in: id) }.reduce(0) { $0 + $1.size } ?? 0
    }

    private func resumeURL(for file: ModelFile, in id: String) -> URL {
        let name = file.path.replacing("/", with: "_")
        return staging(id).appending(path: ".\(name).resume")
    }

    private static func identity(of task: URLSessionTask) -> (id: String, path: String)? {
        guard let parts = task.taskDescription?.split(separator: "\n"), parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }
}

extension ModelDownloader: URLSessionDownloadDelegate {
    public func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite _: Int64,
    ) {
        guard let identity = Self.identity(of: downloadTask) else { return }
        let running = lock.withLock {
            inFlight[downloadTask.taskIdentifier] = totalBytesWritten
            return inFlight.values.reduce(0, +)
        }
        let total = catalog[identity.id]?.totalBytes ?? 0
        update(identity.id, .downloading(received: min(stagedBytes(identity.id) + running, total), total: total))
    }

    public func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL,
    ) {
        guard let identity = Self.identity(of: downloadTask) else { return }
        lock.withLock { _ = inFlight.removeValue(forKey: downloadTask.taskIdentifier) }
        guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
            update(identity.id, .failed(.unavailable))
            return
        }
        // The system deletes `location` when this method returns, so the move must happen here.
        let target = staging(identity.id).appending(path: identity.path)
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: location, to: target)
        } catch {
            update(identity.id, .failed(.noSpace))
        }
    }

    public func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let identity = Self.identity(of: task), let model = catalog[identity.id] else { return }
        lock.withLock { _ = inFlight.removeValue(forKey: task.taskIdentifier) }
        if let error {
            let isUserAction = lock.withLock { pausing.contains(identity.id) }
            guard !isUserAction else { return }
            let info = (error as NSError).userInfo
            if let data = info[NSURLSessionDownloadTaskResumeData] as? Data,
               let file = model.files.first(where: { $0.path == identity.path })
            {
                try? data.write(to: resumeURL(for: file, in: model.id))
            }
            let received = stagedBytes(model.id)
            update(model.id, .paused(received: received, total: model.totalBytes))
            return
        }
        guard case .failed = lock.withLock({ states[model.id] }) else {
            if model.files.allSatisfy({ isStaged($0, in: model.id) }) {
                finish(model)
            }
            return
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession _: URLSession) {
        let completion = lock.withLock {
            let value = backgroundCompletion
            backgroundCompletion = nil
            return value
        }
        completion?()
    }
}
