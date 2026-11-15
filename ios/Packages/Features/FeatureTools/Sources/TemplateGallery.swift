import DesignSystem
import Domain
import FeatureShared
import Localization
import SwiftUI

// The look of the template library: a mark and a color per category, and cards in place of plain rows.

extension TemplateCategory {
    var symbol: String {
        switch self {
        case .general: "square.grid.2x2"
        case .meeting: "person.3"
        case .speech: "megaphone"
        case .interview: "person.text.rectangle"
        case .call: "phone"
        }
    }

    /// One of the accent colors, so that each category keeps its own in both themes.
    var tint: Color {
        let index = TemplateCategory.allCases.firstIndex(of: self) ?? 0
        return Color.dsAccents[index % Color.dsAccents.count]
    }

    var title: String {
        L10n.Templates.category(rawValue)
    }
}

extension SummaryTemplate {
    /// Built-in templates get their own mark. One a person wrote takes its category's.
    var symbol: String {
        switch id {
        case BuiltInTemplates.defaultID: "sparkles"
        case "builtin.minutes": "list.clipboard"
        case "builtin.discussion": "bubble.left.and.bubble.right"
        case "builtin.oneonone": "person.2"
        case "builtin.lecture": "graduationcap"
        case "builtin.interview": "person.text.rectangle"
        case "builtin.call": "phone"
        default: category.symbol
        }
    }

    /// What the summary will hold, in the person's language: the section titles.
    var outline: String {
        sections
            .map { L10n.Summary.sectionTitle($0.title) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// A category in the grid at the top. Opens every template in it.
struct CategoryTile: View {
    let category: TemplateCategory

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Image(systemName: category.symbol)
                .font(.dsIcon)
                .foregroundStyle(category.tint)
                .accessibilityHidden(true)
            Text(category.title)
                .font(.dsRowTitle)
                .foregroundStyle(Color.dsPrimaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .background(Color.dsSurface, in: .rect(cornerRadius: Radius.medium))
        .contentShape(.rect(cornerRadius: Radius.medium))
    }
}

/// One template: its mark, its name, what it holds, and whether it is the default.
struct TemplateCard: View {
    let template: SummaryTemplate
    let isDefault: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Image(systemName: template.symbol)
                .font(.dsIconLarge)
                .foregroundStyle(template.category.tint)
                .padding(.bottom, Spacing.xSmall)
                .accessibilityHidden(true)
            Text(L10n.Summary.templateName(template.name))
                .font(.dsHeading)
                .foregroundStyle(Color.dsPrimaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !template.outline.isEmpty {
                Text(template.outline)
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.small)
            footer
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Spacing.medium)
        .background(Color.dsSurface, in: .rect(cornerRadius: Radius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.medium)
                .strokeBorder(Color.dsSelection, lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: Radius.medium))
    }

    @ViewBuilder
    private var footer: some View {
        if isDefault {
            Label(L10n.Templates.isDefault, systemImage: "star.fill")
                .font(.dsBadge)
                .foregroundStyle(Color.dsAction)
        } else {
            Text(template.isBuiltIn ? L10n.Templates.builtIn : template.category.title)
                .font(.dsBadge)
                .foregroundStyle(Color.dsSecondaryText)
        }
    }
}

/// A section title that opens the whole category: "Meeting >".
struct CategoryHeader: View {
    let category: TemplateCategory

    var body: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: category.symbol)
                .font(.dsHeading)
                .foregroundStyle(category.tint)
                .accessibilityHidden(true)
            Text(category.title)
                .font(.dsSectionTitle)
                .foregroundStyle(Color.dsPrimaryText)
            Image(systemName: "chevron.right")
                .font(.dsNote.weight(.semibold))
                .foregroundStyle(Color.dsSecondaryText)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .tappableTarget()
    }
}

/// Every template in one category, as a grid of cards.
struct CategoryTemplatesView: View {
    let category: TemplateCategory
    let center: SummaryCenter
    let recordings: () async -> [Recording]

    private var templates: [SummaryTemplate] {
        center.userTemplates.filter { $0.category == category }
            + BuiltInTemplates.all.filter { $0.category == category }
    }

    var body: some View {
        ScrollView {
            TemplateGrid(templates: templates, center: center, recordings: recordings)
                .padding(.horizontal, Spacing.medium)
                .padding(.bottom, Spacing.large)
        }
        .screenScrollMargins()
        .screenBackground()
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.templateCategory")
    }
}

/// Cards that wrap into as many columns as fit. One column at the largest text sizes.
struct TemplateGrid: View {
    let templates: [SummaryTemplate]
    let center: SummaryCenter
    let recordings: () async -> [Recording]
    @ScaledMetric(relativeTo: .body) private var minimumWidth: CGFloat = 160

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: Spacing.compact, alignment: .top)],
            spacing: Spacing.compact,
        ) {
            ForEach(templates) { template in
                TemplateLink(template: template, center: center, recordings: recordings)
            }
        }
    }
}

/// A card that opens the template.
struct TemplateLink: View {
    let template: SummaryTemplate
    let center: SummaryCenter
    let recordings: () async -> [Recording]

    var body: some View {
        NavigationLink {
            TemplateDetailView(templateID: template.id, center: center, recordings: recordings)
        } label: {
            TemplateCard(template: template, isDefault: template.id == center.defaultTemplateID)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("template.card")
    }
}
