import SwiftUI

/// Bars for recent audio levels, newest on the right. Hidden from VoiceOver: the screen states the status in text.
public struct WaveformView: View {
    private let levels: [Float]
    private let isActive: Bool

    public init(levels: [Float], isActive: Bool) {
        self.levels = levels
        self.isActive = isActive
    }

    public var body: some View {
        Canvas { context, size in
            let barWidth: CGFloat = 3
            let gap: CGFloat = 3
            let count = Int(size.width / (barWidth + gap))
            let color = isActive ? Color.dsRecord : Color.dsSecondaryText
            for (offset, level) in levels.suffix(count).reversed().enumerated() {
                let height = max(3, CGFloat(level) * size.height)
                let bar = CGRect(
                    x: size.width - CGFloat(offset + 1) * (barWidth + gap),
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height,
                )
                context.fill(Path(roundedRect: bar, cornerRadius: barWidth / 2), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}
