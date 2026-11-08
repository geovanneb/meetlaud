import CryptoKit
import Domain
import Foundation
@testable import ModelDelivery
import Testing

private final class Stub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: (status: Int, data: Data)] = [:]
    nonisolated(unsafe) static var requests: [String] = []
    private static let lock = NSLock()

    static func response(for url: String) -> (status: Int, data: Data)? {
        lock.withLock {
            requests.append(url)
            return responses[url]
        }
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let client,
              let stub = Self.response(for: url.absoluteString),
              let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: stub.data)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@Suite(.serialized)
final class ModelDownloaderTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func model(id: String = UUID().uuidString, files: [(String, Data)]) -> ModelDescriptor {
        ModelDescriptor(
            id: id,
            displayName: "Test",
            roles: [.transcription],
            runtime: .whisperKit,
            files: files.map { path, data in
                let url = "https://models.test/\(id)/\(path)"
                Stub.responses[url] = (200, data)
                // swiftlint:disable:next force_unwrapping
                return ModelFile(path: path, url: URL(string: url)!, size: Int64(data.count), sha256: hash(data))
            },
            languages: ["en"],
        )
    }

    private func downloader(
        _ models: [ModelDescriptor],
        free: Int64 = 100_000_000_000,
        log: @escaping @Sendable (NetworkLogEntry) -> Void = { _ in },
    ) throws -> ModelDownloader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        return try ModelDownloader(
            root: root, catalog: models, configuration: configuration, freeBytes: { free }, log: log,
        )
    }

    private func terminal(_ downloader: ModelDownloader, id: String) async -> InstallState? {
        for await event in downloader.events where event.id == id {
            switch event.state {
            case .ready, .failed, .notInstalled: return event.state
            default: continue
            }
        }
        return nil
    }

    @Test func `a model installs into its folder with every file`() async throws {
        let model = model(files: [("model/a.bin", Data("alpha".utf8)), ("tokenizer.json", Data("{}".utf8))])
        let downloader = try downloader([model])
        await downloader.install(model, allowsCellular: false)
        #expect(await terminal(downloader, id: model.id) == .ready)
        let folder = try #require(downloader.folder(for: model.id))
        #expect(try Data(contentsOf: folder.appending(path: "model/a.bin")) == Data("alpha".utf8))
        #expect(await downloader.installedIDs() == [model.id])
    }

    @Test func `a corrupted file is retried once, and then the install fails cleanly`() async throws {
        var model = model(files: [("a.bin", Data("alpha".utf8))])
        let bad = ModelFile(path: "a.bin", url: model.files[0].url, size: 5, sha256: "wrong")
        model = ModelDescriptor(
            id: model.id, displayName: "Test", roles: [.transcription], runtime: .whisperKit,
            files: [bad], languages: ["en"],
        )
        let downloader = try downloader([model])
        await downloader.install(model, allowsCellular: false)
        #expect(await terminal(downloader, id: model.id) == .failed(.damaged))
        #expect(downloader.folder(for: model.id) == nil, "A damaged model must never be visible")
        #expect(Stub.requests.count(where: { $0 == bad.url.absoluteString }) == 2)
    }

    @Test func `a server error fails the install`() async throws {
        let model = model(files: [("a.bin", Data("alpha".utf8))])
        Stub.responses[model.files[0].url.absoluteString] = (404, Data())
        let downloader = try downloader([model])
        await downloader.install(model, allowsCellular: false)
        #expect(await terminal(downloader, id: model.id) == .failed(.unavailable))
    }

    @Test func `no space stops before downloading`() async throws {
        let model = model(files: [("a.bin", Data("alpha".utf8))])
        let downloader = try downloader([model], free: 1000)
        await downloader.install(model, allowsCellular: false)
        #expect(await downloader.state(of: model.id) == .failed(.noSpace))
        #expect(!Stub.requests.contains(model.files[0].url.absoluteString))
    }

    @Test func `removing a model deletes it`() async throws {
        let model = model(files: [("a.bin", Data("alpha".utf8))])
        let downloader = try downloader([model])
        await downloader.install(model, allowsCellular: false)
        _ = await terminal(downloader, id: model.id)
        try await downloader.remove(model.id)
        #expect(downloader.folder(for: model.id) == nil)
        #expect(await downloader.state(of: model.id) == .notInstalled)
    }

    @Test func `a finished install writes the network log`() async throws {
        let model = model(files: [("a.bin", Data("alpha".utf8))])
        let entries = Entries()
        let downloader = try downloader([model]) { entries.append($0) }
        await downloader.install(model, allowsCellular: false)
        _ = await terminal(downloader, id: model.id)
        #expect(entries.all.map(\.modelID) == [model.id])
    }

    @Test func `staged files are not downloaded again`() async throws {
        let model = model(files: [("a.bin", Data("alpha".utf8)), ("b.bin", Data("beta".utf8))])
        let staged = root.appending(path: ".staging/\(model.id)")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try Data("alpha".utf8).write(to: staged.appending(path: "a.bin"))

        let downloader = try downloader([model])
        await downloader.install(model, allowsCellular: false)
        #expect(await terminal(downloader, id: model.id) == .ready)
        #expect(!Stub.requests.contains(model.files[0].url.absoluteString))
    }

    @Test func `the bundled catalog is complete and points only to allowed hosts`() throws {
        let catalog = try BundledCatalog()
        #expect(!catalog.models.isEmpty)
        for model in catalog.models {
            #expect(!model.license.isEmpty)
            #expect(!model.languages.isEmpty || !model.roles.contains(.transcription))
            for file in model.files {
                #expect(file.url.host() == "huggingface.co")
                #expect(file.sha256.count == 64)
                #expect(file.url.absoluteString.contains("/resolve/"))
                #expect(!file.url.absoluteString.contains("/resolve/main/"), "Revisions must be pinned")
            }
        }
    }

    @Test func `every whisper model carries its tokenizer, so that nothing is fetched outside delivery`() throws {
        for model in try BundledCatalog().models where model.runtime == .whisperKit {
            #expect(model.files.contains { $0.path == "tokenizer.json" })
            #expect(model.files.contains { $0.path == "tokenizer_config.json" })
        }
    }
}

private final class Entries: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [NetworkLogEntry] = []

    func append(_ entry: NetworkLogEntry) {
        lock.withLock { values.append(entry) }
    }

    var all: [NetworkLogEntry] {
        lock.withLock { values }
    }
}
