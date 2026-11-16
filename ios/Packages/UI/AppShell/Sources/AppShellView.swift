import AppRouting
import DesignSystem
import Localization
import SwiftUI

/// The app's navigation frame: a drawer at compact width and a native sidebar at regular width.
///
/// Destination views come in from the composition root, so this module knows no feature.
public struct AppShellView<Content: View, RouteContent: View, Accessory: View, Recorder: View>: View {
    @Bindable private var router: AppRouter
    private let content: (Destination) -> Content
    private let routeContent: (AppRoute) -> RouteContent
    private let accessory: () -> Accessory
    private let recorder: () -> Recorder

    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(
        router: AppRouter,
        @ViewBuilder content: @escaping (Destination) -> Content,
        @ViewBuilder routeContent: @escaping (AppRoute) -> RouteContent,
        @ViewBuilder accessory: @escaping () -> Accessory,
        @ViewBuilder recorder: @escaping () -> Recorder,
    ) {
        self.router = router
        self.content = content
        self.routeContent = routeContent
        self.accessory = accessory
        self.recorder = recorder
    }

    public var body: some View {
        Group {
            if sizeClass == .regular {
                sidebarLayout
            } else {
                drawerLayout
            }
        }
        .fullScreenCover(isPresented: $router.isRecorderPresented, content: recorder)
        .environment(router)
    }

    private var drawerLayout: some View {
        DrawerContainer(
            isOpen: $router.isDrawerOpen,
            isEdgeGestureEnabled: router.isAtRoot,
            closeLabel: L10n.Nav.closeMenu,
        ) {
            SideMenu(selected: router.selected, onSelect: router.select) { router.open(.search) }
        } content: {
            stack(showsMenuButton: true)
        }
    }

    /// On a wide screen a list keeps its place, and what it opens goes in the next column.
    private var usesColumns: Bool {
        [.home, .library, .settings].contains(router.selected)
    }

    @ViewBuilder private var sidebarLayout: some View {
        if usesColumns {
            NavigationSplitView {
                sidebar
            } content: {
                stack(showsMenuButton: false, keepsRoutesInStack: false)
            } detail: {
                detailColumn
            }
            .id("columns")
        } else {
            NavigationSplitView {
                sidebar
            } detail: {
                stack(showsMenuButton: false)
            }
        }
    }

    private var sidebar: some View {
        SideMenu(selected: router.selected, onSelect: router.select) { router.open(.search) }
            .toolbar(removing: .sidebarToggle)
    }

    @ViewBuilder private var detailColumn: some View {
        let destination = router.selected
        if let first = router.path(for: destination).first {
            NavigationStack(path: Binding(
                get: { Array(router.path(for: destination).dropFirst()) },
                set: { router.setPath([first] + $0, for: destination) },
            )) {
                routeContent(first)
                    .navigationDestination(for: AppRoute.self, destination: routeContent)
            }
            .id(first)
        } else {
            Image(systemName: "sidebar.right")
                .font(.dsHero)
                .foregroundStyle(Color.dsSecondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .screenBackground()
                .accessibilityHidden(true)
        }
    }

    private func stack(showsMenuButton: Bool, keepsRoutesInStack: Bool = true) -> some View {
        let destination = router.selected
        return NavigationStack(path: keepsRoutesInStack ? pathBinding(for: destination) : .constant([])) {
            content(destination)
                .safeAreaInset(edge: .bottom) {
                    if destination == .home || destination == .library {
                        PromptBar(placeholder: L10n.Home.askPlaceholder) {
                            router.open(.ask(recording: nil))
                        }
                        .accessibilityIdentifier("prompt.bar")
                    }
                }
                .toolbar {
                    if showsMenuButton {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                router.isDrawerOpen = true
                            } label: {
                                Label(L10n.Nav.openMenu, systemImage: "line.3.horizontal.decrease")
                            }
                            .accessibilityIdentifier("drawer.toggle")
                        }
                    }
                }
                .navigationDestination(for: AppRoute.self, destination: routeContent)
        }
        .id(destination)
        // No transition here. One on this identity replaces the whole drawer, menu included, and the slide never runs.
        // Outside the stack, so that the recording stays visible on every screen.
        .safeAreaInset(edge: .bottom, spacing: 0, content: accessory)
    }

    private func pathBinding(for destination: Destination) -> Binding<[AppRoute]> {
        Binding(
            get: { router.path(for: destination) },
            set: { router.setPath($0, for: destination) },
        )
    }
}
