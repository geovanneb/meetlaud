import Foundation

/// A finished meeting, in the terms of this module. The app adapts its own types to this, so that nothing here knows
/// about the library.
public struct ConnectorMeeting: Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date

    public init(id: UUID, createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
    }
}

/// Where meetings come from.
public protocol ConnectorMeetingSource: Sendable {
    /// Finished meetings, not in the trash.
    func finishedMeetings() async -> [ConnectorMeeting]
    /// Only the content asked for. Returns nil while the meeting is not ready to go, such as still being transcribed.
    func package(for id: UUID, including content: Set<ConnectorContent>) async -> ConnectorPackage?
    func logDelivery(of package: ConnectorPackage, to connector: ConnectorManifest) async
}

/// What already went where. It is what makes sending again safe, and it survives the app closing.
public protocol ConnectorDeliveryLog: Sendable {
    func isDelivered(_ meeting: UUID, to connector: String) -> Bool
    func markDelivered(_ meeting: UUID, to connector: String)
}

public struct UserDefaultsDeliveryLog: ConnectorDeliveryLog, @unchecked Sendable {
    /// Unchecked because UserDefaults is documented as safe across threads, and this holds no other state.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ connector: String) -> String {
        "connectors.delivered.\(connector)"
    }

    public func isDelivered(_ meeting: UUID, to connector: String) -> Bool {
        defaults.stringArray(forKey: key(connector))?.contains(meeting.uuidString) ?? false
    }

    public func markDelivered(_ meeting: UUID, to connector: String) {
        defaults.set(
            (defaults.stringArray(forKey: key(connector)) ?? []) + [meeting.uuidString],
            forKey: key(connector),
        )
    }
}

/// Sends what is pending to each linked connector, one meeting at a time. The phone always starts: nothing here
/// waits for a request. A failure stops that connector until the next chance, and nothing is lost.
public actor ConnectorSync {
    private let registry: ConnectorRegistry
    private let source: any ConnectorMeetingSource
    private let log: any ConnectorDeliveryLog
    private var isRunning = false
    private var runAgain = false

    public init(registry: ConnectorRegistry, source: any ConnectorMeetingSource, log: any ConnectorDeliveryLog) {
        self.registry = registry
        self.source = source
        self.log = log
    }

    /// A call during a run asks for one more, so that a meeting finished meanwhile is not left waiting.
    public func run() async {
        guard !isRunning else {
            runAgain = true
            return
        }
        isRunning = true
        repeat {
            runAgain = false
            for connector in registry.connectors where connector.manifest.availability == .available {
                await deliver(to: connector)
            }
        } while runAgain
        isRunning = false
    }

    private func deliver(to connector: any Connector) async {
        // Only what was recorded after linking. Connecting must not send a whole history no one chose to send.
        guard let since = connector.linkedSince else { return }
        let id = connector.manifest.id
        let pending = await source.finishedMeetings()
            .filter { $0.createdAt >= since && !log.isDelivered($0.id, to: id) }
            .sorted { $0.createdAt < $1.createdAt }
        for meeting in pending {
            guard let package = await source.package(for: meeting.id, including: connector.wantedContent) else {
                continue
            }
            do {
                try await connector.send(package)
            } catch {
                return
            }
            log.markDelivered(meeting.id, to: id)
            await source.logDelivery(of: package, to: connector.manifest)
        }
    }
}
