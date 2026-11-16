@testable import Connectors
import Foundation
import Testing

private actor Inbox {
    var received: [ConnectorPackage] = []

    func add(_ package: ConnectorPackage) {
        received.append(package)
    }
}

/// A connector written the way a real one is, knowing nothing but this module.
private struct TestConnector: Connector {
    var id = "test"
    var availability = ConnectorManifest.Availability.available
    let inbox = Inbox()

    var manifest: ConnectorManifest {
        ConnectorManifest(
            id: id, name: "Test", summary: "A test.", icon: .symbol("star"), category: .productivity,
            transport: .localWiFi, accepts: [.transcript], availability: availability,
        )
    }

    func send(_ package: ConnectorPackage) async throws {
        await inbox.add(package)
    }
}

private func package(_ id: UUID = UUID()) -> ConnectorPackage {
    ConnectorPackage(id: id, title: "Sync", date: .now)
}

struct ConnectorRegistryTests {
    @Test func `a connector plugged in shows up with no other change`() {
        let registry = ConnectorRegistry([TestConnector()])
        #expect(registry.manifests.map(\.id) == ["test"])
        #expect(registry.categories == [.productivity])
        #expect(registry.manifests(in: .productivity).count == 1)
    }

    @Test func `an empty registry shows no category`() {
        #expect(ConnectorRegistry().categories.isEmpty)
    }

    @Test func `the same id twice keeps the first`() {
        let registry = ConnectorRegistry([TestConnector(), TestConnector()])
        #expect(registry.manifests.count == 1)
    }

    @Test func `a package reaches the connector it was sent to`() async throws {
        let connector = TestConnector()
        try await ConnectorRegistry([connector]).send(package(), to: "test")
        #expect(await connector.inbox.received.map(\.title) == ["Sync"])
    }

    @Test func `a connector that is not ready receives nothing`() async {
        let connector = TestConnector(availability: .comingSoon)
        await #expect(throws: ConnectorError.unavailable) {
            try await ConnectorRegistry([connector]).send(package(), to: "test")
        }
        #expect(await connector.inbox.received.isEmpty)
    }

    @Test func `an unknown id is an error, not a silent drop`() async {
        await #expect(throws: ConnectorError.unknownConnector) {
            try await ConnectorRegistry().send(package(), to: "nobody")
        }
    }
}

private final class MemoryLog: ConnectorDeliveryLog, @unchecked Sendable {
    /// Unchecked because the tests use it from one task at a time.
    private var delivered: Set<String> = []

    func isDelivered(_ meeting: UUID, to connector: String) -> Bool {
        delivered.contains("\(connector)/\(meeting)")
    }

    func markDelivered(_ meeting: UUID, to connector: String) {
        delivered.insert("\(connector)/\(meeting)")
    }
}

private actor FakeSource: ConnectorMeetingSource {
    var meetings: [ConnectorMeeting] = []
    var asked: [Set<ConnectorContent>] = []
    var notReady: Set<UUID> = []
    var logged = 0

    init(_ meetings: [ConnectorMeeting], notReady: Set<UUID> = []) {
        self.meetings = meetings
        self.notReady = notReady
    }

    func finishedMeetings() -> [ConnectorMeeting] {
        meetings
    }

    func package(for id: UUID, including content: Set<ConnectorContent>) -> ConnectorPackage? {
        asked.append(content)
        return notReady.contains(id) ? nil : ConnectorPackage(id: id, title: "Sync", date: .now)
    }

    func logDelivery(of _: ConnectorPackage, to _: ConnectorManifest) {
        logged += 1
    }
}

private struct LinkedConnector: Connector {
    var since: Date? = Date(timeIntervalSince1970: 1000)
    var wanted: Set<ConnectorContent> = [.audio]
    var failing = false
    let inbox = Inbox()

    var manifest: ConnectorManifest {
        ConnectorManifest(
            id: "linked", name: "Linked", summary: "", icon: .symbol("star"), category: .productivity,
            transport: .localWiFi, accepts: [.audio], availability: .available,
        )
    }

    var linkedSince: Date? {
        since
    }

    var wantedContent: Set<ConnectorContent> {
        wanted
    }

    func send(_ package: ConnectorPackage) async throws {
        if failing {
            throw ConnectorError.unavailable
        }
        await inbox.add(package)
    }
}

struct ConnectorSyncTests {
    private let old = ConnectorMeeting(id: UUID(), createdAt: Date(timeIntervalSince1970: 500))
    private let new = ConnectorMeeting(id: UUID(), createdAt: Date(timeIntervalSince1970: 2000))

    private func sync(
        _ connector: LinkedConnector,
        _ source: FakeSource,
        log: any ConnectorDeliveryLog = MemoryLog(),
    ) -> ConnectorSync {
        ConnectorSync(registry: ConnectorRegistry([connector]), source: source, log: log)
    }

    @Test func `only meetings recorded after linking are sent`() async {
        let connector = LinkedConnector()
        await sync(connector, FakeSource([old, new])).run()
        #expect(await connector.inbox.received.map(\.id) == [new.id])
    }

    @Test func `nothing is sent until the person links`() async {
        let connector = LinkedConnector(since: nil)
        await sync(connector, FakeSource([new])).run()
        #expect(await connector.inbox.received.isEmpty)
    }

    @Test func `a delivered meeting is not sent twice`() async {
        let connector = LinkedConnector()
        let log = MemoryLog()
        let source = FakeSource([new])
        await sync(connector, source, log: log).run()
        await sync(connector, source, log: log).run()
        #expect(await connector.inbox.received.count == 1)
        #expect(await source.logged == 1)
    }

    @Test func `a failure stays pending for the next chance`() async {
        let log = MemoryLog()
        let source = FakeSource([new])
        await sync(LinkedConnector(failing: true), source, log: log).run()
        #expect(!log.isDelivered(new.id, to: "linked"))
        let working = LinkedConnector()
        await sync(working, source, log: log).run()
        #expect(await working.inbox.received.count == 1)
    }

    @Test func `a meeting that is not ready waits, and does not block the next`() async {
        let connector = LinkedConnector()
        let waiting = ConnectorMeeting(id: UUID(), createdAt: Date(timeIntervalSince1970: 1500))
        await sync(connector, FakeSource([waiting, new], notReady: [waiting.id])).run()
        #expect(await connector.inbox.received.map(\.id) == [new.id])
    }

    @Test func `the source is asked only for what the person agreed to share`() async {
        let connector = LinkedConnector(wanted: [.audio, .photos])
        let source = FakeSource([new])
        await sync(connector, source).run()
        #expect(await source.asked == [[.audio, .photos]])
    }
}
