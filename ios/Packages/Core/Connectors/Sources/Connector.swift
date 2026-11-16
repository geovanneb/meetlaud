import Foundation

/// The contract between Meetlaud and anything that can receive meeting material.
///
/// This module is the only thing a connector and the app share. It imports nothing of ours, so a connector never
/// sees the library, the database, or a model: it gets only the `ConnectorPackage` a person chose to send.
/// To add one, see docs/connectors.md.
public protocol Connector: Sendable {
    var manifest: ConnectorManifest { get }
    /// When this device was linked to the other app, or nil if it is not.
    var linkedSince: Date? { get }
    /// What the person agreed to share. Anything else never reaches the connector.
    var wantedContent: Set<ConnectorContent> { get }
    /// Fires when the other app may be reachable, so that delivery starts on its own.
    func peerChanges() -> AsyncStream<Void>
    /// Receives one meeting. Must be safe to call again with the same meeting.
    func send(_ package: ConnectorPackage) async throws
}

public extension Connector {
    var linkedSince: Date? {
        nil
    }

    var wantedContent: Set<ConnectorContent> {
        []
    }

    func peerChanges() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}

/// What a connector can be given.
public enum ConnectorContent: String, CaseIterable, Sendable {
    case audio, transcript, photos, notes
}

public struct ConnectorPackage: Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var date: Date
    public var audioFile: URL?
    public var transcript: String?
    public var photos: [URL]

    public init(
        id: UUID,
        title: String,
        date: Date,
        audioFile: URL? = nil,
        transcript: String? = nil,
        photos: [URL] = [],
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.audioFile = audioFile
        self.transcript = transcript
        self.photos = photos
    }
}

public enum ConnectorIcon: Equatable, Sendable {
    case symbol(String)
    /// An image the connector carries in its own bundle.
    case image(URL)
}

public struct ConnectorManifest: Identifiable, Equatable, Sendable {
    /// How data would travel. Local means the two devices talk directly, with no server in between.
    public enum Transport: Equatable, Sendable {
        case localWiFi
    }

    public enum Category: String, CaseIterable, Sendable {
        case productivity
    }

    public enum Availability: Equatable, Sendable {
        case available
        case comingSoon
    }

    public let id: String
    public let name: String
    /// A sentence or two on what the other app is, in the person's language.
    public let summary: String
    public let icon: ConnectorIcon
    public let category: Category
    public let transport: Transport
    public let accepts: Set<ConnectorContent>
    public let availability: Availability

    public init(
        id: String,
        name: String,
        summary: String,
        icon: ConnectorIcon,
        category: Category,
        transport: Transport,
        accepts: Set<ConnectorContent>,
        availability: Availability,
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.icon = icon
        self.category = category
        self.transport = transport
        self.accepts = accepts
        self.availability = availability
    }
}

public enum ConnectorError: Error, Equatable {
    case unknownConnector
    case unavailable
}

/// The connectors in this build. The app fills it in one place, and everything else reads from it.
public struct ConnectorRegistry: Sendable {
    /// The first of two connectors with the same id wins: an id is what a saved choice would point at.
    public init(_ connectors: [any Connector] = []) {
        var seen: Set<String> = []
        self.connectors = connectors.filter { seen.insert($0.manifest.id).inserted }
    }

    public let connectors: [any Connector]

    public var manifests: [ConnectorManifest] {
        connectors.map(\.manifest)
    }

    /// Only categories with something in them, so that a screen never shows an empty heading.
    public var categories: [ConnectorManifest.Category] {
        ConnectorManifest.Category.allCases.filter { !manifests(in: $0).isEmpty }
    }

    public func manifests(in category: ConnectorManifest.Category) -> [ConnectorManifest] {
        manifests.filter { $0.category == category }
    }

    public func connector(id: String) -> (any Connector)? {
        connectors.first { $0.manifest.id == id }
    }

    public func send(_ package: ConnectorPackage, to id: String) async throws {
        try await ready(id).send(package)
    }

    private func ready(_ id: String) throws -> any Connector {
        guard let connector = connector(id: id) else { throw ConnectorError.unknownConnector }
        guard connector.manifest.availability == .available else { throw ConnectorError.unavailable }
        return connector
    }
}
