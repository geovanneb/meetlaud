import Foundation
import Network

/// Finds the linked computer. It announces itself by name, so this works on a hotspot and on a shared network.
enum GTDDiscovery {
    static let serviceType = "_gtd-inbox._tcp"

    /// Refuses anything that is not on this network. Whatever a name or a code says, nothing here leaves it.
    static func isLocal(_ host: String) -> Bool {
        let address = host.lowercased()
        let parts = address.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            return parts[0] == 10 || parts[0] == 127 || (parts[0] == 192 && parts[1] == 168)
                || (parts[0] == 169 && parts[1] == 254) || (parts[0] == 172 && (16 ... 31).contains(parts[1]))
        }
        return false
    }

    static func url(host: String, port: Int) throws -> URL {
        guard isLocal(host), let url = URL(string: "http://\(host):\(port)") else { throw GTDError.notLocal }
        return url
    }

    /// A browser in the foreground. Each sighting of the computer fires `found`.
    @MainActor
    final class Watcher {
        private var browser: NWBrowser?

        func start(fingerprint: String, found: @escaping @Sendable (NWEndpoint) -> Void) {
            let browser = NWBrowser(
                for: .bonjourWithTXTRecord(type: GTDDiscovery.serviceType, domain: nil),
                using: NWParameters(),
            )
            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    if case let .bonjour(record) = result.metadata, record["fp"] == fingerprint {
                        found(result.endpoint)
                    }
                }
            }
            browser.start(queue: .main)
            self.browser = browser
        }

        func stop() {
            browser?.cancel()
            browser = nil
        }
    }

    /// Turns a name into an IPv4 address and a port that the upload can use.
    static func resolve(_ endpoint: NWEndpoint) async -> URL? {
        let parameters = NWParameters.tcp
        (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let connection = NWConnection(to: endpoint, using: parameters)
        return await withCheckedContinuation { continuation in
            let once = Once(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    var url: URL?
                    if case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint {
                        let name = "\(host)".split(separator: "%").first.map(String.init) ?? "\(host)"
                        url = try? GTDDiscovery.url(host: name, port: Int(port.rawValue))
                    }
                    connection.cancel()
                    once.resume(url)
                case .failed, .cancelled:
                    once.resume(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    /// `NWConnection` can report more than one end state, and a continuation resumes once.
    private final class Once: @unchecked Sendable {
        /// Unchecked because the lock guards the only state.
        private var continuation: CheckedContinuation<URL?, Never>?
        private let lock = NSLock()

        init(_ continuation: CheckedContinuation<URL?, Never>) {
            self.continuation = continuation
        }

        func resume(_ value: URL?) {
            lock.lock()
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(returning: value)
        }
    }
}
