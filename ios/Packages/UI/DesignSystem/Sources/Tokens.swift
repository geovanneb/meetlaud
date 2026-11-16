import SwiftUI
import UIKit

/// Semantic colors. Features use these, never raw values.
public extension Color {
    static let dsBackground = Color(light: 0xF9F9F9, dark: 0x0F0F0F)
    static let dsSurface = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    /// Primary text. Lists mute `.primary` inside section headers, so headers need a real color.
    static let dsPrimaryText = Color(light: 0x111111, dark: 0xF5F5F5)
    /// Secondary text. The system's `.secondary` fails the contrast audit on these backgrounds.
    static let dsSecondaryText = Color(light: 0x505050, dark: 0xB8B8B8)
    static let dsSelection = Color(light: 0xEBEBEB, dark: 0x2C2C2E)
    /// Reserved for recording. Using it elsewhere weakens what it means.
    static let dsRecord = Color(light: 0xC62A2F, dark: 0xFF6369)
    static let dsAction = Color(light: 0x2F6FD0, dark: 0x5E9BF0)
    /// Text and icons on top of `dsAction`. White fails contrast on the lighter blue of Dark Mode.
    static let dsOnAction = Color(light: 0xFFFFFF, dark: 0x0F0F0F)
    /// Work that finished well: a step that is done. Never the only sign, a symbol always goes with it.
    static let dsPositive = Color(light: 0x2E7D32, dark: 0x6CCB72)
    /// Something that needs the person, without being an error: waiting for a charger, a hot device.
    static let dsAttention = Color(light: 0x9A5B00, dark: 0xF2B04E)
    /// The empty part of a bar or a ring.
    static let dsTrack = Color(light: 0xE4E4E4, dark: 0x343437)
    /// Parts of one whole, as in a storage bar. In order, and each one apart from the next in both themes.
    /// Red stays out: it belongs to recording.
    static let dsSeries: [Color] = [
        dsAction,
        Color(light: 0x1C8C84, dark: 0x4CC7BD),
        Color(light: 0x8A5CC7, dark: 0xB494EE),
        Color(light: 0xB36B00, dark: 0xF0A94A),
        Color(light: 0x7A7A7A, dark: 0x9A9A9E),
    ]
    /// Marks that tell kinds apart, such as template categories. The series hues, darker where needed so that each
    /// one reaches 4.5:1 on the background and on a surface, in both themes.
    static let dsAccents: [Color] = [
        dsAction,
        Color(light: 0x14756E, dark: 0x4CC7BD),
        Color(light: 0x8A5CC7, dark: 0xB494EE),
        Color(light: 0x995C00, dark: 0xF0A94A),
        Color(light: 0x6B6B6B, dark: 0xA8A8AD),
    ]

    private init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1,
        )
    }
}

public enum Spacing {
    public static let xSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let compact: CGFloat = 12
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 24
    public static let xLarge: CGFloat = 32
}

public enum Radius {
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 14
    public static let drawer: CGFloat = 28
}

/// The type scale. Every label in the app uses one of these, so each level means the same on every screen.
/// All of them follow Dynamic Type.
public extension Font {
    /// The largest number on a screen, such as the recording timer.
    static let dsDisplay = Font.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit()
    /// What a screen is about, in its content: a meeting's title, or "My files".
    static let dsPageTitle = Font.title2.bold()
    /// The title of an empty state or a locked screen.
    static let dsSectionTitle = Font.title3.bold()
    /// A heading inside a card or a document.
    static let dsHeading = Font.headline
    /// The main line of a row, and running text.
    static let dsRowTitle = Font.body
    /// A row in the side menu, which is read from further away than a list.
    static let dsMenuRow = Font.title3
    /// The line under a row's title, and short status text.
    static let dsMeta = Font.subheadline
    /// Hints, explanations, and anything else that supports a row.
    static let dsNote = Font.footnote
    /// A small tag next to a title, such as "Best" or "Suggested".
    static let dsBadge = Font.caption
    /// A moment in the audio. Digits keep their width, so that times line up and do not jitter.
    static let dsTimestamp = Font.footnote.monospacedDigit()
    /// A symbol that stands in for an illustration.
    static let dsHero = Font.largeTitle
    /// An icon-only button.
    static let dsIcon = Font.title3
    /// An icon-only button that leads its row or bar.
    static let dsIconLarge = Font.title2
}

public extension View {
    /// Apple's minimum tap target. Goes inside a button's label: outside, it grows the layout but not the target.
    func tappableTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(.rect)
    }

    /// The standard list. Grouped and not plain, because a plain list pins its section titles to the top and lets rows
    /// slide under them. Every row keeps a clear background, so it reads as one flat page that scrolls as a whole.
    func screenList() -> some View {
        listStyle(.grouped)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(Spacing.medium)
            .screenScrollMargins()
    }

    /// Keeps the first line clear of the fade under the navigation bar, which dims it below readable contrast, and
    /// keeps the last line readable behind the bars that float at the bottom.
    func screenScrollMargins() -> some View {
        contentMargins(.top, Spacing.medium, for: .scrollContent)
            .scrollEdgeEffectHidden(true, for: .bottom)
    }

    /// Standard background for a full screen.
    func screenBackground() -> some View {
        background(Color.dsBackground.ignoresSafeArea())
    }
}
