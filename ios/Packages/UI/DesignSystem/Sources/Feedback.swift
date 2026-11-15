import SwiftUI

// The app's feedback vocabulary. Anything that takes longer than a moment shows one of these, so the person can
// always tell working from stuck (Nielsen's first heuristic, and Maister: an unexplained, uncertain wait feels
// longest). The rules, the same on every screen:
//
// - A known fraction gets a bar or a ring that fills. An unknown one gets motion that never stops, never a bar
//   standing still at one value, which reads as frozen.
// - Long work names its steps, so the person sees where it is and what comes next.
// - Reduce Motion turns every movement into a gentle pulse of opacity. State is never told by motion alone.
//
// Custom because iOS has no circular ring with a value and no indeterminate bar. Each one carries its own
// accessibility label and value, and the text around it grows with Dynamic Type.

// MARK: - Ring

/// A small ring that fills to a fraction, or spins when the fraction is unknown.
public struct ProgressRing: View {
    private let fraction: Double?
    private let tint: Color
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 20
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTurning = false

    /// `fraction` nil spins: work is going on, and how much is left is not known.
    public init(fraction: Double?, tint: Color = .dsAction) {
        self.fraction = fraction.map { min(max($0, 0), 1) }
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            Circle().stroke(Color.dsTrack, lineWidth: lineWidth)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(fraction, 0.02))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .motion(Motion.standard, value: fraction)
            } else if reduceMotion {
                Circle()
                    .stroke(tint, lineWidth: lineWidth)
                    .opacity(isTurning ? 0.9 : 0.3)
                    .animation(.easeInOut(duration: 1).repeatForever(), value: isTurning)
            } else {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(isTurning ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: isTurning)
            }
        }
        .frame(width: size, height: size)
        .onAppear { isTurning = true }
        .accessibilityHidden(true)
    }

    private var lineWidth: CGFloat {
        max(2, size / 8)
    }
}

// MARK: - Bar

/// A thin bar. With a fraction it fills like the system's. Without one, a light sweeps across it, so the person
/// sees that work is going on even when no number can be given.
public struct ActivityBar: View {
    private let fraction: Double?
    private let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSweeping = false

    public init(fraction: Double?, tint: Color = .dsAction) {
        self.fraction = fraction.map { min(max($0, 0), 1) }
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.dsTrack)
                if let fraction {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(proxy.size.height, proxy.size.width * fraction))
                        .motion(Motion.standard, value: fraction)
                } else if reduceMotion {
                    Capsule()
                        .fill(tint)
                        .opacity(isSweeping ? 0.7 : 0.2)
                        .animation(.easeInOut(duration: 1).repeatForever(), value: isSweeping)
                } else {
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * 0.3)
                        .offset(x: isSweeping ? proxy.size.width : -proxy.size.width * 0.3)
                        .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false), value: isSweeping)
                }
            }
            .clipShape(.capsule)
        }
        .frame(height: 6)
        .onAppear { isSweeping = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Steps

/// One step of a longer piece of work.
public struct ProcessStep: Identifiable, Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case waiting, active, done
    }

    public let id: String
    public let title: String
    public let state: State

    public init(id: String, title: String, state: State) {
        self.id = id
        self.title = title
        self.state = state
    }
}

/// What VoiceOver says for each state. Passed in, since text lives in the String Catalog.
public struct ProcessStepLabels: Sendable {
    public let waiting: String
    public let active: String
    public let done: String

    public init(waiting: String, active: String, done: String) {
        self.waiting = waiting
        self.active = active
        self.done = done
    }
}

/// The steps of a piece of work, in order: done ones checked, the current one turning, the rest waiting.
public struct StepList: View {
    private let steps: [ProcessStep]
    private let labels: ProcessStepLabels

    public init(_ steps: [ProcessStep], labels: ProcessStepLabels) {
        self.steps = steps
        self.labels = labels
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            ForEach(steps) { step in
                HStack(spacing: Spacing.small) {
                    icon(step.state)
                        .frame(minWidth: Spacing.large)
                    Text(step.title)
                        .font(.dsMeta)
                        .fontWeight(step.state == .active ? .semibold : .regular)
                        .foregroundStyle(step.state == .waiting ? Color.dsSecondaryText : Color.dsPrimaryText)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(step.title)
                .accessibilityValue(value(step.state))
            }
        }
        .motion(Motion.standard, value: steps)
    }

    @ViewBuilder private func icon(_ state: ProcessStep.State) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.dsMeta)
                .foregroundStyle(Color.dsPositive)
                .transition(.scale.combined(with: .opacity))
        case .active:
            ProgressRing(fraction: nil)
        case .waiting:
            Image(systemName: "circle.dashed")
                .font(.dsMeta)
                .foregroundStyle(Color.dsSecondaryText)
        }
    }

    private func value(_ state: ProcessStep.State) -> String {
        switch state {
        case .waiting: labels.waiting
        case .active: labels.active
        case .done: labels.done
        }
    }
}

// MARK: - Badge

/// A short state next to a title: "Transcribing 42%", "Queued", "Waiting for a charger". A symbol or a ring always
/// goes with the words, so the state reads at a glance and never by color alone.
public struct StatusBadge: View {
    public enum Tone: Sendable {
        case working, waiting, attention, done
    }

    private let text: String
    private let tone: Tone
    private let fraction: Double?
    private let symbol: String?

    /// A working badge shows a ring: filled to `fraction`, or turning without one. Other tones show `symbol`.
    public init(_ text: String, tone: Tone, fraction: Double? = nil, symbol: String? = nil) {
        self.text = text
        self.tone = tone
        self.fraction = fraction
        self.symbol = symbol
    }

    public var body: some View {
        HStack(spacing: Spacing.xSmall) {
            if tone == .working {
                ProgressRing(fraction: fraction, tint: color)
                    .scaleEffect(0.8)
            } else if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
            }
            Text(text)
                .foregroundStyle(tone == .attention ? color : Color.dsPrimaryText)
                .contentTransition(.numericText())
        }
        .font(.dsNote)
        .padding(.vertical, Spacing.xSmall / 2)
        .padding(.horizontal, Spacing.small)
        .background(Color.dsSelection.opacity(0.7), in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch tone {
        case .working: .dsAction
        case .waiting: .dsSecondaryText
        case .attention: .dsAttention
        case .done: .dsPositive
        }
    }
}

// MARK: - Card

public extension View {
    /// A raised group on the page, for status and summaries that belong together.
    func dsCard() -> some View {
        padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsSurface, in: .rect(cornerRadius: Radius.medium))
            .overlay(RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(Color.dsSelection))
    }
}

// MARK: - Usage

/// One part of a whole, such as what recordings take on the device.
public struct UsagePart: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let value: Int64
    /// What to read out and show for the value, such as "1.2 GB".
    public let formatted: String

    public init(id: String, title: String, value: Int64, formatted: String) {
        self.id = id
        self.title = title
        self.value = value
        self.formatted = formatted
    }
}

/// A bar split into parts, with a legend under it: the shape of the Settings storage screen people know from
/// iPhone Storage. `total` is the whole the bar stands for; the space not taken stays as track.
public struct UsageBar: View {
    private let parts: [UsagePart]
    private let total: Int64
    private let showsLegend: Bool

    /// Without a legend, the rows that follow show each part's color with `UsageDot`.
    public init(parts: [UsagePart], total: Int64? = nil, showsLegend: Bool = true) {
        self.parts = parts
        self.total = max(total ?? parts.reduce(0) { $0 + $1.value }, 1)
        self.showsLegend = showsLegend
    }

    /// The color of the part at `index`, the same in the bar and in any row that names it.
    public static func color(at index: Int) -> Color {
        Color.dsSeries[index % Color.dsSeries.count]
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            GeometryReader { proxy in
                HStack(spacing: 1) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, part in
                        Rectangle()
                            .fill(color(index))
                            .frame(width: max(2, proxy.size.width * CGFloat(part.value) / CGFloat(total)))
                    }
                    Spacer(minLength: 0)
                }
                .background(Color.dsTrack)
                .clipShape(.rect(cornerRadius: Radius.small / 2))
                .motion(Motion.standard, value: parts)
            }
            .frame(height: 12)
            .accessibilityHidden(true)

            if showsLegend {
                legend
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                HStack(spacing: Spacing.small) {
                    UsageDot(index: index)
                    Text(part.title)
                        .font(.dsMeta)
                        .foregroundStyle(Color.dsPrimaryText)
                    Spacer(minLength: Spacing.small)
                    Text(part.formatted)
                        .font(.dsMeta.monospacedDigit())
                        .foregroundStyle(Color.dsSecondaryText)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var visible: [UsagePart] {
        parts.filter { $0.value > 0 }
    }

    private func color(_ index: Int) -> Color {
        Self.color(at: index)
    }
}

/// The small swatch that ties a row to its part of a `UsageBar`.
public struct UsageDot: View {
    private let index: Int
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 10

    public init(index: Int) {
        self.index = index
    }

    public var body: some View {
        Circle()
            .fill(UsageBar.color(at: index))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
