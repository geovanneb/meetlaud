import AppRouting
import AppShell
import Domain
import FeatureLibrary
import FeatureModels
import FeatureRecording
import ModelDelivery
import SwiftUI
import SystemBridges

@main
struct MeetlaudApp: App {
    @State private var container = Self.makeContainer()
    @UIApplicationDelegateAdaptor(ModelDeliveryAppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ThemePreferences.key) private var theme = AppTheme.system.rawValue
    @AppStorage(SpotlightPreferences.key) private var showsInSpotlight = false

    private var colorScheme: ColorScheme? {
        switch AppTheme(rawValue: theme) {
        case .light: .light
        case .dark: .dark
        default: nil
        }
    }

    /// The app cannot do anything useful without its storage, and there is nothing to recover to.
    private static func makeContainer() -> AppContainer {
        do {
            let container = try AppContainer()
            ModelDeliveryAppDelegate.downloader = container.downloader
            return container
        } catch {
            fatalError("Storage is unavailable: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            let composition = Composition(container: container)
            AppShellView(
                router: container.router,
                content: { composition.screen(for: $0) },
                routeContent: { composition.screen(for: $0) },
                accessory: { RecordingPill(controller: container.recorder) },
                recorder: { RecordingScreen(controller: container.recorder) },
            )
            .modifier(RecorderPrompts(controller: container.recorder))
            .modifier(ImportPrompts(library: container.library))
            .sheet(isPresented: Bindable(container.models).showsSetup) {
                ModelSetupView(controller: container.models) {
                    container.router.open(.modelSettings)
                }
            }
            .task { container.models.offerSetupIfNeeded() }
            // Only while active: iOS does not let an app keep a browser or a connection open behind the screen.
            .task(id: scenePhase == .active) {
                if scenePhase == .active {
                    await container.keepConnectorsInSync()
                }
            }
            .task(id: showsInSpotlight) { await container.keepSpotlight(enabled: showsInSpotlight) }
            .onContinueUserActivity(SpotlightIndex.activityType) { activity in
                if let id = SpotlightIndex.recording(from: activity) {
                    container.router.open(.recording(id, at: nil))
                }
            }
            .preferredColorScheme(colorScheme)
            .onChange(of: scenePhase, initial: true) { _, phase in
                container.setActive(phase == .active)
                container.sceneChanged(phase)
            }
            .onOpenURL { url in
                // Files arrive from "Open in Meetlaud" in other apps. Links go through the router.
                if url.isFileURL {
                    container.library.importFiles([url])
                } else {
                    container.router.open(url: url)
                }
            }
        }
        .commands { AppCommands(router: container.router, recorder: container.recorder) }
    }
}
