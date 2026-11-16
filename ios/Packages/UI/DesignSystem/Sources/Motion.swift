import SwiftUI

/// The app's timing. Short and calm, and the same for the same kind of change on every screen. Kept on the quick
/// side, so that the app answers the finger before the eye starts waiting.
public enum Motion {
    /// State inside a control: a selection, a highlight, a button changing.
    public static let quick = Animation.smooth(duration: 0.16)
    /// Something entering or leaving a screen, or a folder opening.
    public static let standard = Animation.smooth(duration: 0.25)
    /// The side menu. Halfway there in 50 ms, and settled in about 200, as measured frame by frame at 60 frames a
    /// second.
    public static let drawer = Animation.spring(duration: 0.2, bounce: 0)
    /// Replaces movement when Reduce Motion is on.
    public static let reduced = Animation.easeInOut(duration: 0.2)

    /// Swaps one view for another. The animation belongs to the transition, so it never reaches inside the views.
    public static var crossfade: AnyTransition {
        .opacity.animation(quick)
    }
}

public extension View {
    /// Enters from just below and fades. With Reduce Motion it only fades.
    func riseTransition() -> some View {
        modifier(RiseTransition())
    }

    /// `animation(_:value:)` with Reduce Motion respected.
    func motion(_ animation: Animation, value: some Equatable) -> some View {
        modifier(ReducibleAnimation(animation: animation, value: value))
    }
}

private struct RiseTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: Spacing.compact)))
    }
}

private struct ReducibleAnimation<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? Motion.reduced : animation, value: value)
    }
}
