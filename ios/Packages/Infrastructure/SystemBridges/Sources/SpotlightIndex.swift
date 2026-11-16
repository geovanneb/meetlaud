import CoreSpotlight
import Domain
import Foundation

/// Puts meeting titles in iOS search. The index stays on the device, and transcripts never go in.
public struct SpotlightIndex: SystemSearchIndex {
    private static let domain = "com.meetlaud.app.recordings"

    /// What iOS sends when someone opens a result. Named here so that the app stays out of CoreSpotlight.
    public static let activityType = CSSearchableItemActionType

    public static func recording(from activity: NSUserActivity) -> RecordingID? {
        (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(RecordingID.init(string:))
    }

    public init() {}

    public func index(_ recordings: [Recording]) async {
        let items = recordings.filter { $0.deletedAt == nil && $0.status == .ready }.map { recording in
            let attributes = CSSearchableItemAttributeSet(contentType: .audio)
            attributes.title = recording.title
            attributes.contentCreationDate = recording.createdAt
            return CSSearchableItem(
                uniqueIdentifier: recording.id.rawValue.uuidString,
                domainIdentifier: Self.domain,
                attributeSet: attributes,
            )
        }
        await removeAll()
        try? await CSSearchableIndex.default().indexSearchableItems(items)
    }

    public func removeAll() async {
        try? await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [Self.domain])
    }
}
