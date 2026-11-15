import SwiftUI

/// Side menu for compact widths. iOS has no native drawer for iPhone (D-001).
///
/// The content slides aside, and the menu settles into place behind it, growing slightly and fading in. Measured from
/// a reference recording of a side menu that felt right. With Reduce Motion, the menu fades in on top.
public struct DrawerContainer<Menu: View, Content: View>: View {
    @Binding private var isOpen: Bool
    private let isEdgeGestureEnabled: Bool
    private let closeLabel: String
    private let menu: Menu
    private let content: Content

    /// What the drawer shows. It opens at once, under the finger. It closes a beat after `isOpen`, because choosing a
    /// destination builds a whole screen on the main thread. If the slide started at the same moment, its clock would
    /// run during that work and the first frames would never be seen.
    @State private var isShown: Bool
    @State private var translation: CGFloat = 0
    @State private var isDragging = false
    /// Where the finger was when the drag was recognized, so the content does not jump by the recognition distance.
    @State private var dragOrigin: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        isOpen: Binding<Bool>,
        isEdgeGestureEnabled: Bool,
        closeLabel: String,
        @ViewBuilder menu: () -> Menu,
        @ViewBuilder content: () -> Content,
    ) {
        _isOpen = isOpen
        _isShown = State(initialValue: isOpen.wrappedValue)
        self.isEdgeGestureEnabled = isEdgeGestureEnabled
        self.closeLabel = closeLabel
        self.menu = menu()
        self.content = content()
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = DrawerGeometry.menuWidth(forContainer: proxy.size.width)
            let progress = DrawerGeometry.progress(isOpen: isShown, translation: translation, menuWidth: width)

            ZStack(alignment: .leading) {
                menuLayer(width: width, progress: progress)
                contentLayer(width: width, progress: progress)
            }
            .animation(settling, value: progress)
            .contentShape(.rect)
            .gesture(dragGesture(menuWidth: width))
            .onChange(of: isOpen) { _, open in follow(open) }
        }
        .background(Color.dsBackground.ignoresSafeArea())
    }

    private func follow(_ open: Bool) {
        guard open != isShown else { return }
        guard !open else {
            isShown = true
            return
        }
        Task {
            // Runs once the main thread is free, which is after the new screen is built.
            try? await Task.sleep(for: .milliseconds(16))
            isShown = isOpen
        }
    }

    /// How the drawer moves. Under a finger it does not animate at all: it follows the finger exactly.
    private var settling: Animation? {
        guard !isDragging else { return nil }
        return reduceMotion ? Motion.reduced : Motion.drawer
    }

    /// The drawer animates its own shell and nothing inside it. A screen that opens from the menu must not inherit the
    /// slide, or its bars and rows fly in from nowhere: `transaction` stops the animation at the content's edge.
    /// Only when the drawer moves: a plain `transaction` here also cancelled every animation the screens start
    /// themselves, such as a folder opening.
    private func menuLayer(width: CGFloat, progress: CGFloat) -> some View {
        menu
            .frame(width: width)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.dsBackground)
            .transaction(value: progress) { $0.animation = nil }
            .scaleEffect(reduceMotion ? 1 : DrawerGeometry.menuScale(progress: progress))
            .opacity(reduceMotion ? progress : DrawerGeometry.menuOpacity(progress: progress))
            .zIndex(reduceMotion ? 1 : 0)
            .allowsHitTesting(isOpen)
            .accessibilityHidden(!isOpen)
            .accessibilityAddTraits(isOpen ? .isModal : [])
            .accessibilityAction(.escape) { isOpen = false }
    }

    private func contentLayer(width: CGFloat, progress: CGFloat) -> some View {
        let radius = reduceMotion ? 0 : Radius.drawer * progress
        return content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(!isOpen)
            .accessibilityHidden(isOpen)
            // Opaque, so that the menu never shows through while two screens cross-fade.
            .background(Color.dsBackground.ignoresSafeArea())
            // The page fades back as the menu comes forward, the way the reference does.
            .overlay {
                Color.dsBackground
                    .opacity(DrawerGeometry.contentFade * progress)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .transaction(value: progress) { $0.animation = nil }
            // A mask and not a clip: the shape reaches past the safe area, while the content stays inside it, so that
            // the screen's bottom bars keep their real space above the home indicator.
            .mask { RoundedRectangle(cornerRadius: radius).ignoresSafeArea() }
            // A shadow on a plain shape: on the content itself it would redraw the whole screen on every frame.
            .background {
                RoundedRectangle(cornerRadius: radius)
                    .fill(Color.dsBackground)
                    .shadow(color: .black.opacity(0.12 * progress), radius: 16, x: -4)
                    .ignoresSafeArea()
            }
            .offset(x: reduceMotion ? 0 : width * progress)
            .overlay {
                if isOpen {
                    Color.clear
                        .contentShape(.rect)
                        .offset(x: reduceMotion ? 0 : width)
                        .onTapGesture { isOpen = false }
                        .accessibilityLabel(closeLabel)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { isOpen = false }
                }
            }
    }

    private func dragGesture(menuWidth: CGFloat) -> DrawerPan {
        DrawerPan(
            canBegin: canBeginDrag,
            onChanged: { distance in
                if !isDragging {
                    dragOrigin = distance
                    isDragging = true
                }
                translation = distance - dragOrigin
            },
            onEnded: { distance, predicted in
                defer {
                    translation = 0
                    isDragging = false
                }
                guard isDragging, let distance, let predicted else { return }
                let settled = DrawerGeometry.settles(
                    openFrom: isOpen,
                    translation: distance,
                    predictedTranslation: predicted,
                    menuWidth: menuWidth,
                )
                // Together, because the translation resets here: a finger leaves nothing to build first.
                isShown = settled
                isOpen = settled
            },
        )
    }

    private func canBeginDrag(translation: CGSize, startX: CGFloat) -> Bool {
        guard abs(translation.width) > abs(translation.height) else { return false }
        if isOpen {
            return translation.width < 0
        }
        return isEdgeGestureEnabled
            && translation.width > 0
            && startX <= DrawerGeometry.edgeActivationWidth
    }
}

/// The drawer's drag, as a UIKit pan. A SwiftUI `DragGesture` over the whole screen takes every sideways touch as
/// soon as it moves, also the ones the drawer then ignores: a segmented control under the finger lost its touch, so
/// its selection could be tapped but not dragged. A pan that refuses to begin leaves the touch where it was.
private struct DrawerPan: UIGestureRecognizerRepresentable {
    /// The movement so far, and where on the screen the finger started.
    let canBegin: (_ translation: CGSize, _ startX: CGFloat) -> Bool
    let onChanged: (_ distance: CGFloat) -> Void
    /// The distance and where a flick would carry it, or nil when the system took the touch away.
    let onEnded: (_ distance: CGFloat?, _ predicted: CGFloat?) -> Void

    /// How far a flick carries on, in seconds of its speed. Close to what `DragGesture` predicts.
    private static let flickReach: CGFloat = 0.25

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        context.coordinator.canBegin = canBegin
        return recognizer
    }

    func updateUIGestureRecognizer(_: UIPanGestureRecognizer, context: Context) {
        context.coordinator.canBegin = canBegin
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context _: Context) {
        let distance = recognizer.translation(in: nil).x
        switch recognizer.state {
        case .began, .changed:
            onChanged(distance)
        case .ended:
            onEnded(distance, distance + recognizer.velocity(in: nil).x * Self.flickReach)
        case .cancelled, .failed:
            onEnded(nil, nil)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canBegin: (CGSize, CGFloat) -> Bool = { _, _ in false }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let moved = pan.translation(in: nil)
            return canBegin(CGSize(width: moved.x, height: moved.y), pan.location(in: nil).x - moved.x)
        }

        /// Lists keep scrolling while the drawer watches, as they did before.
        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
        ) -> Bool {
            true
        }
    }
}

/// The drawer's math, kept pure so it can be tested without a UI.
enum DrawerGeometry {
    static let edgeActivationWidth: CGFloat = 24
    private static let widthFraction: CGFloat = 0.76
    private static let maximumWidth: CGFloat = 340
    /// How much the page fades back with the menu open.
    static let contentFade = 0.43

    static func menuWidth(forContainer width: CGFloat) -> CGFloat {
        min(width * widthFraction, maximumWidth)
    }

    /// The menu stays in place and grows into it.
    static func menuScale(progress: CGFloat) -> CGFloat {
        0.97 + 0.03 * progress
    }

    static func menuOpacity(progress: CGFloat) -> CGFloat {
        0.6 + 0.4 * progress
    }

    /// How open the drawer is, from 0 to 1.
    static func progress(isOpen: Bool, translation: CGFloat, menuWidth: CGFloat) -> CGFloat {
        guard menuWidth > 0 else { return isOpen ? 1 : 0 }
        let start: CGFloat = isOpen ? 1 : 0
        return min(max(start + translation / menuWidth, 0), 1)
    }

    /// Where the drawer rests after a drag, using the predicted end so a quick flick counts.
    static func settles(
        openFrom isOpen: Bool,
        translation: CGFloat,
        predictedTranslation: CGFloat,
        menuWidth: CGFloat,
    ) -> Bool {
        let predicted = max(abs(predictedTranslation), abs(translation)) * (predictedTranslation < 0 ? -1 : 1)
        return progress(isOpen: isOpen, translation: predicted, menuWidth: menuWidth) > 0.5
    }
}
