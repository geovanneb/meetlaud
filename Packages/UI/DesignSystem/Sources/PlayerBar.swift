import SwiftUI

public struct PlayerBarLabels {
    public let play: String
    public let pause: String
    public let back: String
    public let forward: String
    public let position: String
    public let speed: String

    public init(play: String, pause: String, back: String, forward: String, position: String, speed: String) {
        self.play = play
        self.pause = pause
        self.back = back
        self.forward = forward
        self.position = position
        self.speed = speed
    }
}

/// Timeline with markers, transport controls, and speed.
public struct PlayerBar: View {
    private let time: TimeInterval
    private let duration: TimeInterval
    private let isPlaying: Bool
    private let markers: [TimeInterval]
    private let rate: Float
    private let labels: PlayerBarLabels
    private let onSeek: (TimeInterval) -> Void
    private let onToggle: () -> Void
    private let onRate: (Float) -> Void

    @State private var scrubbing: TimeInterval?
    public static let rates: [Float] = [0.75, 1, 1.25, 1.5, 2]

    public init(
        time: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool,
        markers: [TimeInterval],
        rate: Float,
        labels: PlayerBarLabels,
        onSeek: @escaping (TimeInterval) -> Void,
        onToggle: @escaping () -> Void,
        onRate: @escaping (Float) -> Void,
    ) {
        self.time = time
        self.duration = duration
        self.isPlaying = isPlaying
        self.markers = markers
        self.rate = rate
        self.labels = labels
        self.onSeek = onSeek
        self.onToggle = onToggle
        self.onRate = onRate
    }

    public var body: some View {
        VStack(spacing: Spacing.small) {
            timeline
            HStack {
                Text((scrubbing ?? time).clock)
                Spacer()
                Text(duration.clock)
            }
            .font(.dsTimestamp)
            .foregroundStyle(Color.dsSecondaryText)
            .accessibilityHidden(true)
            controls
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
    }

    private var timeline: some View {
        Slider(
            value: Binding(
                get: { scrubbing ?? time },
                set: { scrubbing = $0 },
            ),
            in: 0 ... max(duration, 1),
        ) { editing in
            if !editing, let scrubbing {
                onSeek(scrubbing)
                self.scrubbing = nil
            }
        }
        .overlay(alignment: .leading) {
            GeometryReader { proxy in
                ForEach(markers, id: \.self) { marker in
                    Capsule()
                        .fill(Color.dsAction)
                        .frame(width: 3, height: 12)
                        .offset(x: proxy.size.width * marker / max(duration, 1), y: proxy.size.height / 2 + 8)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .accessibilityLabel(labels.position)
        .accessibilityValue(time.clock)
    }

    private var controls: some View {
        HStack(spacing: Spacing.large) {
            Menu {
                ForEach(Self.rates, id: \.self) { value in
                    Button(value.formatted() + "×") { onRate(value) }
                }
            } label: {
                Text(rate.formatted() + "×")
                    .font(.dsTimestamp)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(labels.speed)
            .accessibilityIdentifier("player.speed")

            Spacer()

            Button(labels.back, systemImage: "gobackward.15") { onSeek(time - 15) }
                .labelStyle(.iconOnly)
                .font(.dsIconLarge)

            Button(isPlaying ? labels.pause : labels.play, systemImage: isPlaying ? "pause.fill" : "play.fill") {
                onToggle()
            }
            .keyboardShortcut(.space, modifiers: [])
            .labelStyle(.iconOnly)
            .font(.dsHero)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityIdentifier("player.toggle")

            Button(labels.forward, systemImage: "goforward.30") { onSeek(time + 30) }
                .labelStyle(.iconOnly)
                .font(.dsIconLarge)

            Spacer()

            Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
        }
        .foregroundStyle(.primary)
    }
}
