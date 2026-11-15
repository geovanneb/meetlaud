import Domain
import Foundation

/// Parses `meetlaud://` URLs. Input is untrusted, so anything unexpected returns nil.
public enum DeepLink {
    public static let scheme = "meetlaud"

    public static func route(from url: URL) -> AppRoute? {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == scheme,
            let host = components.host?.lowercased()
        else { return nil }

        let path = components.path.split(separator: "/").map(String.init)
        let query = components.queryItems ?? []

        switch (host, path.count) {
        case ("record", 0): return .record
        case ("recording", 1): return recording(id: path[0], query: query)
        case ("ask", 0): return ask(query: query)
        case ("settings", 1) where path[0] == "models": return .modelSettings
        default: return nil
        }
    }

    private static func recording(id rawID: String, query: [URLQueryItem]) -> AppRoute? {
        guard let id = RecordingID(string: rawID) else { return nil }
        guard let rawTime = query.value(for: "t") else { return .recording(id, at: nil) }
        guard let time = TimeInterval(rawTime), time.isFinite, time >= 0 else { return nil }
        return .recording(id, at: time)
    }

    private static func ask(query: [URLQueryItem]) -> AppRoute? {
        guard let rawID = query.value(for: "recording") else { return .ask(recording: nil) }
        return RecordingID(string: rawID).map { .ask(recording: $0) }
    }
}

private extension [URLQueryItem] {
    func value(for name: String) -> String? {
        first { $0.name == name }?.value
    }
}
