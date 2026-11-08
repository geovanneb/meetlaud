import UIKit

/// iOS wakes the app to report background downloads through this callback. SwiftUI has no equivalent. It lives here
/// so that the app target stays free of network code.
public final class ModelDeliveryAppDelegate: NSObject, UIApplicationDelegate {
    @MainActor public static var downloader: ModelDownloader?

    public func application(
        _: UIApplication,
        handleEventsForBackgroundURLSession _: String,
        completionHandler: @escaping @Sendable () -> Void,
    ) {
        Self.downloader?.handleBackgroundEvents(completion: completionHandler)
    }
}
