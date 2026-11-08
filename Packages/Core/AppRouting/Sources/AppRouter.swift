import Foundation
import Observation

/// The single source of navigation state.
///
/// Each destination keeps its own path, so switching in the side menu preserves where the user was.
@MainActor
@Observable
public final class AppRouter {
    public private(set) var selected: Destination
    public var isDrawerOpen = false
    /// The recording screen, which floats above every destination.
    public var isRecorderPresented = false
    private var paths: [Destination: [AppRoute]] = [:]

    public init(selected: Destination = .home) {
        self.selected = selected
    }

    public func select(_ destination: Destination) {
        selected = destination
        isDrawerOpen = false
    }

    public func path(for destination: Destination) -> [AppRoute] {
        paths[destination, default: []]
    }

    public func setPath(_ path: [AppRoute], for destination: Destination) {
        paths[destination] = path
    }

    /// The side menu edge gesture only works at a root, to avoid fighting the back swipe.
    public var isAtRoot: Bool {
        path(for: selected).isEmpty
    }

    /// Opens a screen on top of the current destination, keeping the user's place.
    public func push(_ route: AppRoute) {
        paths[selected, default: []].append(route)
    }

    /// Goes back one screen.
    public func pop() {
        _ = paths[selected]?.popLast()
    }

    public func open(_ route: AppRoute) {
        select(route.destination)
        if route == .record {
            isRecorderPresented = true
        }
        if route.isPushed {
            paths[route.destination, default: []].append(route)
        }
    }

    /// Returns false when the URL is not a valid route, which is a normal outcome for untrusted input.
    @discardableResult
    public func open(url: URL) -> Bool {
        guard let route = DeepLink.route(from: url) else { return false }
        open(route)
        return true
    }
}
