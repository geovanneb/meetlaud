import DesignSystem
import Domain
import Localization
import SwiftUI

/// The summary as a branching outline. Custom because no native control draws a tree with branches. Each node is a
/// plain button, so VoiceOver reads it in order, Dynamic Type grows it, and Reduce Motion is handled by `motion`.
struct MindMapView: View {
    let model: DetailModel
    let root: MindMapNode
    @State private var collapsed: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.compact) {
                    Text(root.title)
                        .font(.dsPageTitle)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(root.children, content: branch)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.medium)
                .motion(Motion.standard, value: collapsed)
            }
            .screenBackground()
            .navigationTitle(L10n.Summary.mindMap)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.done) { dismiss() }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.mindMap")
    }

    private func branch(_ node: MindMapNode) -> some View {
        let isOpen = !collapsed.contains(node.id)
        return VStack(alignment: .leading, spacing: Spacing.small) {
            Button {
                if isOpen {
                    collapsed.insert(node.id)
                } else {
                    collapsed.remove(node.id)
                }
            } label: {
                HStack(spacing: Spacing.small) {
                    Image(systemName: "chevron.right")
                        .font(.dsBadge)
                        .rotationEffect(isOpen ? .degrees(90) : .zero)
                        .accessibilityHidden(true)
                    Text(L10n.Summary.sectionTitle(node.title))
                        .font(.dsHeading)
                    Spacer(minLength: Spacing.small)
                    Text(verbatim: "\(node.children.count)")
                        .font(.dsBadge)
                        .foregroundStyle(Color.dsSecondaryText)
                }
                .foregroundStyle(Color.dsPrimaryText)
                .padding(.horizontal, Spacing.compact)
                .tappableTarget()
                .background(Color.dsSurface, in: .rect(cornerRadius: Radius.medium))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOpen ? .isSelected : [])
            .accessibilityIdentifier("mindmap.branch")

            if isOpen {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    ForEach(node.children, content: leaf)
                }
                .padding(.leading, Spacing.compact)
                .overlay(alignment: .leading) {
                    // The branch line that makes this read as a tree and not as a list.
                    Rectangle()
                        .fill(Color.dsSelection)
                        .frame(width: 2)
                        .accessibilityHidden(true)
                }
                .padding(.leading, Spacing.compact)
                .riseTransition()
            }
        }
    }

    private func leaf(_ node: MindMapNode) -> some View {
        Button {
            if let time = node.time {
                model.play(from: time)
                dismiss()
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Text(model.display(node.title))
                    .font(.dsRowTitle)
                    .foregroundStyle(Color.dsPrimaryText)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if let time = node.time {
                    Text(time.clock)
                        .font(.dsTimestamp)
                        .foregroundStyle(Color.dsAction)
                }
            }
            .padding(.vertical, Spacing.xSmall)
            .tappableTarget()
        }
        .buttonStyle(.plain)
        .disabled(node.time == nil || !model.hasAudio)
        .accessibilityIdentifier("mindmap.leaf")
    }
}
