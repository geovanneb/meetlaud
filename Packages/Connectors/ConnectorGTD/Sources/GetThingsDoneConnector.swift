import Connectors
import ConnectorsUI
import Foundation
import Network
import SwiftUI

/// Hands meetings to the person's own Get Things Done, on their own network, sealed for that one computer.
/// The phone always starts, and the computer never asks for anything. See docs/connectors.md.
public struct GetThingsDoneConnector: ConnectorWithSettings {
    let store: GTDStore
    /// A meeting holds at most 10 files on the computer: the recording, the transcript, and these.
    private static let maxPhotos = 8

    public init(defaults: UserDefaults = .standard) {
        store = GTDStore(defaults: defaults)
    }

    public var manifest: ConnectorManifest {
        ConnectorManifest(
            id: "gtd",
            name: "Get Things Done",
            summary: GTDText.summary,
            icon: Bundle.module.url(forResource: "gtd-icon", withExtension: "png").map(ConnectorIcon.image)
                ?? .symbol("checkmark.circle"),
            category: .productivity,
            transport: .localWiFi,
            accepts: [.audio, .transcript, .photos],
            availability: .available,
        )
    }

    public var linkedSince: Date? {
        store.link?.linkedAt
    }

    /// Audio always, and the rest only if the person turned it on.
    public var wantedContent: Set<ConnectorContent> {
        var content: Set<ConnectorContent> = [.audio]
        if store.defaults.bool(forKey: GTDStore.transcriptsKey) {
            content.insert(.transcript)
        }
        if store.defaults.bool(forKey: GTDStore.photosKey) {
            content.insert(.photos)
        }
        return content
    }

    @MainActor
    public func settingsView() -> AnyView {
        AnyView(GTDSettingsView(store: store))
    }

    public func peerChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            guard let fingerprint = store.link?.fingerprint else {
                continuation.finish()
                return
            }
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { _ in continuation.yield() }
            monitor.start(queue: .global())
            Task { @MainActor in
                let watcher = GTDDiscovery.Watcher()
                watcher.start(fingerprint: fingerprint) { _ in continuation.yield() }
                continuation.onTermination = { _ in
                    monitor.cancel()
                    Task { @MainActor in watcher.stop() }
                }
            }
        }
    }

    public func send(_ package: ConnectorPackage) async throws {
        guard let link = store.link else { throw GTDError.notLinked }
        let identity = try store.identity()
        let publicKey = identity.publicKey.rawRepresentation
        let key = try GTDCrypto.sharedKey(privateKey: identity, peer: link.computerKey)
        let base = try await locate(link)
        let client = GTDClient(base: base, deviceID: GTDCrypto.deviceID(publicKey: publicKey), key: key)

        let folder = FileManager.default.temporaryDirectory.appending(path: "gtd-\(package.id.uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = try outgoing(package, folder: folder)
        try await client.deliver(package, files: files, day: Self.day(of: package.date))
    }

    private func outgoing(_ package: ConnectorPackage, folder: URL) throws -> [GTDClient.Outgoing] {
        var files: [GTDClient.Outgoing] = []
        if let audio = package.audioFile {
            files.append(GTDClient.Outgoing(name: "recording.\(audio.pathExtension)", url: audio))
        }
        if let transcript = package.transcript {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: "transcript.vtt")
            try transcript.write(to: file, atomically: true, encoding: .utf8)
            files.append(GTDClient.Outgoing(name: "transcript.vtt", url: file))
        }
        for (index, photo) in package.photos.prefix(Self.maxPhotos).enumerated() {
            files.append(GTDClient.Outgoing(name: "photo-\(index + 1).\(photo.pathExtension)", url: photo))
        }
        return files
    }

    static func day(of date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }

    /// By name first, because addresses change between networks. The addresses from pairing are the fallback.
    private func locate(_ link: GTDLink) async throws -> URL {
        if let found = await firstSighting(of: link.fingerprint) {
            return found
        }
        for host in link.hosts {
            if let url = try? GTDDiscovery.url(host: host, port: link.port), await isListening(url) {
                return url
            }
        }
        throw GTDError.notFound
    }

    private func firstSighting(of fingerprint: String) async -> URL? {
        let stream = AsyncStream<URL?> { continuation in
            Task { @MainActor in
                let watcher = GTDDiscovery.Watcher()
                watcher.start(fingerprint: fingerprint) { endpoint in
                    Task { await continuation.yield(GTDDiscovery.resolve(endpoint)) }
                }
                let timeout = Task {
                    try? await Task.sleep(for: .seconds(4))
                    continuation.yield(nil)
                }
                continuation.onTermination = { _ in
                    timeout.cancel()
                    Task { @MainActor in watcher.stop() }
                }
            }
        }
        for await url in stream {
            return url
        }
        return nil
    }

    private func isListening(_ url: URL) async -> Bool {
        var request = URLRequest(url: url.appending(path: "v1/offer"), timeoutInterval: 3)
        request.httpMethod = "POST"
        // Any answer means something is there. Without a paired id it can only be refused.
        return await (try? URLSession.shared.data(for: request)) != nil
    }

    /// Runs when a code is scanned. The link is saved only after both sides proved they saw it.
    static func link(code: GTDPairingCode, store: GTDStore, name: String) async throws {
        let identity = try store.identity()
        var lastError: any Error = GTDError.notFound
        for host in code.hosts {
            do {
                let base = try GTDDiscovery.url(host: host, port: code.port)
                try await GTDClient.pair(
                    base: base, code: code, publicKey: identity.publicKey.rawRepresentation, name: name,
                )
                store.save(GTDLink(
                    computerName: code.name, computerKey: code.publicKey, port: code.port, hosts: code.hosts,
                    linkedAt: Date(),
                ))
                return
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
