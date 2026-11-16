@testable import AppRouting
import Domain
import Foundation
import Testing

@MainActor
struct AppRouterTests {
    @Test func `selecting closes the drawer`() {
        let router = AppRouter()
        router.isDrawerOpen = true
        router.select(.library)
        #expect(router.selected == .library)
        #expect(router.isDrawerOpen == false)
    }

    @Test func `each destination keeps its own path`() {
        let router = AppRouter()
        let route = AppRoute.recording(RecordingID(), at: nil)
        router.open(route)
        router.select(.home)
        #expect(router.path(for: .library) == [route])
        #expect(router.path(for: .home).isEmpty)
    }

    @Test func `root state follows the selected path`() {
        let router = AppRouter()
        #expect(router.isAtRoot)
        router.open(.modelSettings)
        #expect(router.selected == .settings)
        #expect(!router.isAtRoot)
    }

    @Test func `non pushed routes only select`() {
        let router = AppRouter()
        router.open(.ask(recording: nil))
        #expect(router.selected == .ask)
        #expect(router.path(for: .ask).isEmpty)
    }

    @Test func `invalid urls do not navigate`() throws {
        let router = AppRouter(selected: .tools)
        let url = try #require(URL(string: "meetlaud://nope"))
        #expect(router.open(url: url) == false)
        #expect(router.selected == .tools)
    }

    @Test func `record URL only shows the screen`() throws {
        let router = AppRouter(selected: .tools)
        let url = try #require(URL(string: "meetlaud://record"))
        #expect(router.open(url: url))
        #expect(router.selected == .home)
        #expect(router.isRecorderPresented)
    }

    @Test func `push stays on the current destination`() {
        let router = AppRouter(selected: .home)
        let route = AppRoute.recording(RecordingID(), at: nil)
        router.push(route)
        #expect(router.selected == .home)
        #expect(router.path(for: .home) == [route])
    }
}
