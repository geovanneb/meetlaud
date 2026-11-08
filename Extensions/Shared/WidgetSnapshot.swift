import Foundation

/// What widgets may show. Written by the app, and only when the person chose to show meeting content.
struct WidgetSnapshot: Codable, Equatable {
    struct Event: Codable, Equatable {
        let title: String
        let start: Date
    }

    struct Meeting: Codable, Equatable, Identifiable {
        let id: UUID
        let title: String
        let date: Date
    }

    var nextEvent: Event?
    var recent: [Meeting] = []

    /// Set from the build settings, so a fork can sign with its own App Group.
    private static let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String

    private static var file: URL? {
        guard let group else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appending(path: "widget.json")
    }

    static func load() -> Self? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func save() {
        guard var file = Self.file, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? file.setResourceValues(values)
    }

    /// Nothing about a meeting stays behind once the person turns this off.
    static func clear() {
        guard let file else { return }
        try? FileManager.default.removeItem(at: file)
    }
}
