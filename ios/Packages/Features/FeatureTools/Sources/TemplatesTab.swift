import DesignSystem
import Domain
import FeatureShared
import Localization
import SwiftUI
import UniformTypeIdentifiers

/// The template library: categories first, then a row of cards per category.
struct TemplatesTab: View {
    let center: SummaryCenter
    let recordings: () async -> [Recording]
    @State private var query = ""
    @State private var editing: SummaryTemplate?
    @State private var isDrafting = false
    @State private var isImporting = false
    @State private var importFailed = false
    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 220
    @ScaledMetric(relativeTo: .body) private var tileWidth: CGFloat = 170

    private func matches(_ template: SummaryTemplate) -> Bool {
        query.isEmpty || L10n.Summary.templateName(template.name).localizedCaseInsensitiveContains(query)
    }

    private var mine: [SummaryTemplate] {
        center.userTemplates.filter(matches)
    }

    private func builtIn(_ category: TemplateCategory) -> [SummaryTemplate] {
        BuiltInTemplates.all.filter { $0.category == category && matches($0) }
    }

    private var results: [SummaryTemplate] {
        mine + TemplateCategory.allCases.flatMap(builtIn)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                if query.isEmpty {
                    categoryGrid
                    if !mine.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.compact) {
                            Text(L10n.Templates.mine)
                                .font(.dsSectionTitle)
                                .foregroundStyle(Color.dsPrimaryText)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.horizontal, Spacing.medium)
                            cardRow(mine)
                        }
                    }
                    ForEach(TemplateCategory.allCases, id: \.self) { category in
                        let templates = builtIn(category)
                        if !templates.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                                NavigationLink {
                                    CategoryTemplatesView(category: category, center: center, recordings: recordings)
                                } label: {
                                    CategoryHeader(category: category)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityHint(L10n.Templates.seeAll)
                                .accessibilityIdentifier("templates.section.\(category.rawValue)")
                                .padding(.horizontal, Spacing.medium)
                                cardRow(templates)
                            }
                        }
                    }
                } else {
                    TemplateGrid(templates: results, center: center, recordings: recordings)
                        .padding(.horizontal, Spacing.medium)
                }
            }
            .padding(.bottom, Spacing.large)
        }
        .screenScrollMargins()
        .overlay {
            if results.isEmpty {
                EmptyState(title: L10n.Library.noResults, message: "", symbol: "magnifyingglass")
            }
        }
        .searchable(text: $query, prompt: L10n.Templates.search)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(L10n.Templates.new, systemImage: "square.and.pencil") { editing = .blank }
                        .accessibilityIdentifier("templates.new")
                    Button(L10n.Templates.createWithAI, systemImage: "sparkles") { isDrafting = true }
                        .accessibilityIdentifier("templates.ai")
                    Button(L10n.Templates.importFile, systemImage: "square.and.arrow.down") { isImporting = true }
                } label: {
                    Label(L10n.Home.add, systemImage: "plus")
                }
                .accessibilityIdentifier("templates.add")
            }
        }
        .sheet(item: $editing) { template in
            TemplateEditor(template: template) { saved in
                Task { await center.save(saved) }
            }
        }
        .sheet(isPresented: $isDrafting) {
            TemplateDraftSheet(center: center) { editing = $0 }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], onCompletion: importFile)
        .alert(L10n.Templates.importFailed, isPresented: $importFailed) {
            Button(L10n.Common.ok) {}
        }
        .task { await center.reloadTemplates() }
    }

    /// The categories, two rows that scroll sideways, each row as tall as its tallest tile. Each one opens every
    /// template in it.
    private var categoryGrid: some View {
        let all = TemplateCategory.allCases
        let half = (all.count + 1) / 2
        let rows = [Array(all[..<half]), Array(all[half...])]
        return VStack(alignment: .leading, spacing: Spacing.compact) {
            Text(L10n.Templates.categories)
                .font(.dsSectionTitle)
                .foregroundStyle(Color.dsPrimaryText)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Spacing.medium)
            ScrollView(.horizontal) {
                Grid(alignment: .topLeading, horizontalSpacing: Spacing.compact, verticalSpacing: Spacing.compact) {
                    ForEach(rows, id: \.self) { row in
                        GridRow {
                            ForEach(row, id: \.self) { category in
                                NavigationLink {
                                    CategoryTemplatesView(category: category, center: center, recordings: recordings)
                                } label: {
                                    CategoryTile(category: category)
                                }
                                .buttonStyle(.plain)
                                .containerRelativeFrame(.horizontal) { width, _ in min(tileWidth, width * 0.42) }
                                .accessibilityIdentifier("templates.category.\(category.rawValue)")
                            }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Spacing.medium, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    /// A row of cards that scrolls sideways, with the next card peeking in.
    private func cardRow(_ templates: [SummaryTemplate]) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Spacing.compact) {
                ForEach(templates) { template in
                    TemplateLink(template: template, center: center, recordings: recordings)
                        .containerRelativeFrame(.horizontal) { width, _ in min(cardWidth, width * 0.8) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, Spacing.medium, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }

    private func importFile(_ result: Result<URL, any Error>) {
        Task {
            do {
                let url = try result.get()
                let isScoped = url.startAccessingSecurityScopedResource()
                defer {
                    if isScoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                _ = try await center.importTemplate(from: Data(contentsOf: url))
            } catch {
                importFailed = true
            }
        }
    }
}
