import AppRouting
import Connectors
import ConnectorsUI
import DesignSystem
import Domain
import FeatureShared
import Localization
import SwiftUI
import UniformTypeIdentifiers

/// Skills, templates, and connectors, one tab each.
public struct ToolsView: View {
    private enum Tab: Hashable {
        case skills, templates, connectors
    }

    private let center: SummaryCenter
    private let skills: SkillLibrary
    private let connectors: ConnectorRegistry
    private let recordings: () async -> [Recording]
    @State private var tab = Tab.skills

    public init(
        center: SummaryCenter,
        skills: SkillLibrary,
        connectors: ConnectorRegistry,
        recordings: @escaping () async -> [Recording],
    ) {
        self.center = center
        self.skills = skills
        self.connectors = connectors
        self.recordings = recordings
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.Tools.section, selection: $tab) {
                Text(L10n.Tools.skills).tag(Tab.skills)
                Text(L10n.Tools.templates).tag(Tab.templates)
                Text(L10n.Tools.connectors).tag(Tab.connectors)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .accessibilityIdentifier("tools.tabs")

            Group {
                switch tab {
                case .skills: SkillsTab(library: skills)
                case .templates: TemplatesTab(center: center, recordings: recordings)
                case .connectors: ConnectorsTab(registry: connectors)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.Nav.tools)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.tools")
    }
}

/// Saved ways of answering. "Use" starts a chat that follows the skill.
struct SkillsTab: View {
    let library: SkillLibrary
    @State private var editing: Skill?
    @State private var isImporting = false
    @State private var importFailed = false
    @Environment(AppRouter.self) private var router

    private func importFile(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let isScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            try library.save(SkillCodec.decode(Data(contentsOf: url)))
        } catch {
            importFailed = true
        }
    }

    var body: some View {
        List {
            Section(title: L10n.Skills.mine) {
                if library.mine.isEmpty {
                    Text(L10n.Skills.mineEmpty)
                        .font(.dsMeta)
                        .foregroundStyle(Color.dsSecondaryText)
                        .listRowBackground(Color.clear)
                }
                ForEach(library.mine) { skill in
                    row(skill)
                        .contentShape(.rect)
                        .onTapGesture { editing = skill }
                        .swipeActions {
                            Button(L10n.Library.delete, systemImage: "trash", role: .destructive) {
                                library.delete(skill)
                            }
                        }
                }
            }
            .listSectionSeparator(.hidden, edges: .top)
            Section(title: L10n.Skills.official) {
                ForEach(BuiltInSkills.all, content: row)
            }
            .listSectionSeparator(.hidden, edges: .top)
        }
        .screenList()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(L10n.Skills.new, systemImage: "square.and.pencil") {
                        editing = Skill(name: "", summary: "", instructions: "")
                    }
                    .accessibilityIdentifier("skills.new")
                    Button(L10n.Templates.importFile, systemImage: "square.and.arrow.down") { isImporting = true }
                } label: {
                    Label(L10n.Home.add, systemImage: "plus")
                }
                .accessibilityIdentifier("skills.add")
            }
        }
        .sheet(item: $editing) { skill in
            SkillEditor(skill: skill, onSave: library.save)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], onCompletion: importFile)
        .alert(L10n.Templates.importFailed, isPresented: $importFailed) {
            Button(L10n.Common.ok) {}
        }
    }

    private func row(_ skill: Skill) -> some View {
        HStack(spacing: Spacing.medium) {
            RowLabel(skill.displayName, detail: skill.displaySummary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button(L10n.Skills.use) { router.push(.askSkill(skill.id)) }
                .secondaryAction(.small)
                .accessibilityIdentifier("skill.use")
        }
        .listRowBackground(Color.clear)
    }
}

private struct SkillEditor: View {
    @State var skill: Skill
    let onSave: (Skill) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.Skills.name, text: $skill.name)
                        .accessibilityIdentifier("skill.name")
                    TextField(L10n.Skills.summary, text: $skill.summary, axis: .vertical)
                        .lineLimit(1 ... 3)
                }
                Section {
                    TextField(L10n.Skills.instructions, text: $skill.instructions, axis: .vertical)
                        .lineLimit(5 ... 12)
                        .onChange(of: skill.instructions) { _, text in
                            if text.count > Skill.instructionsLimit {
                                skill.instructions = String(text.prefix(Skill.instructionsLimit))
                            }
                        }
                        .accessibilityIdentifier("skill.instructions")
                } footer: {
                    Text(L10n.Skills.instructionsNote)
                        .foregroundStyle(Color.dsSecondaryText)
                }
            }
            .navigationTitle(skill.name.isEmpty ? L10n.Skills.new : L10n.Skills.edit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save) {
                        onSave(skill)
                        dismiss()
                    }
                    .disabled(!skill.isValid)
                    .accessibilityIdentifier("skill.save")
                }
            }
        }
    }
}

/// What can be connected, by category. It reads the registry and knows no connector by name.
struct ConnectorsTab: View {
    let registry: ConnectorRegistry
    @State private var selected: ConnectorManifest?

    var body: some View {
        List {
            ForEach(registry.categories, id: \.self) { category in
                Section(title: title(of: category)) {
                    ForEach(registry.manifests(in: category), content: row)
                }
                .listSectionSeparator(.hidden, edges: .top)
            }
            Text(L10n.Connectors.note)
                .font(.dsNote)
                .foregroundStyle(Color.dsSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .screenList()
        .sheet(item: $selected) { ConnectorSheet(manifest: $0, registry: registry) }
    }

    private func title(of category: ConnectorManifest.Category) -> String {
        switch category {
        case .productivity: L10n.Connectors.productivity
        }
    }

    private func row(_ connector: ConnectorManifest) -> some View {
        Button {
            selected = connector
        } label: {
            HStack(spacing: Spacing.compact) {
                ConnectorIconView(icon: connector.icon)
                RowLabel(connector.name, detail: connector.transport.title)
                Spacer(minLength: 0)
                if connector.availability == .comingSoon || registry.connector(id: connector.id)?.linkedSince != nil {
                    Text(connector.availability == .comingSoon ? L10n.Common.comingSoon : L10n.Connectors.connected)
                        .font(.dsBadge)
                        .foregroundStyle(Color.dsSecondaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.dsNote)
                    .foregroundStyle(Color.dsSecondaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("connector.\(connector.id)")
    }
}

private extension ConnectorManifest.Transport {
    var title: String {
        switch self {
        case .localWiFi: L10n.Connectors.localWiFi
        }
    }
}

/// What the other app is, what it would receive, and the way to start.
private struct ConnectorSheet: View {
    let manifest: ConnectorManifest
    let registry: ConnectorRegistry
    @State private var height: CGFloat = 420
    @State private var isOpen = false

    private var settings: (any ConnectorWithSettings)? {
        registry.connector(id: manifest.id) as? (any ConnectorWithSettings)
    }

    private var isConnected: Bool {
        registry.connector(id: manifest.id)?.linkedSince != nil
    }

    var body: some View {
        // Scrolls only when large text makes the content taller than the screen.
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                ConnectorIconView(icon: manifest.icon, baseSize: 56)
                SheetHeader(title: manifest.name, closeLabel: L10n.Common.close)
                Text(manifest.summary)
                    .font(.dsRowTitle)
                    .foregroundStyle(Color.dsPrimaryText)
                VStack(alignment: .leading, spacing: Spacing.small) {
                    Text(L10n.Connectors.shares)
                        .font(.dsHeading)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(ConnectorContent.allCases.filter(manifest.accepts.contains), id: \.self) { content in
                        Label(content.title, systemImage: content.symbol)
                            .font(.dsMeta)
                            .foregroundStyle(Color.dsSecondaryText)
                    }
                }
                Text(manifest.transport.title)
                    .font(.dsNote)
                    .foregroundStyle(Color.dsSecondaryText)
                Button {
                    isOpen = true
                } label: {
                    Text(buttonTitle)
                        .frame(maxWidth: .infinity)
                }
                .primaryAction()
                .disabled(manifest.availability != .available || settings == nil)
                .accessibilityIdentifier("connector.connect")
            }
            .padding(Spacing.large)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(height)])
        .presentationBackground(Color.dsSurface)
        .sheet(isPresented: $isOpen) {
            if let settings {
                NavigationStack {
                    settings.settingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(L10n.Common.done) { isOpen = false }
                            }
                        }
                }
            }
        }
        .accessibilityIdentifier("screen.connector")
    }

    private var buttonTitle: String {
        guard manifest.availability == .available else { return L10n.Common.comingSoon }
        return isConnected ? L10n.Connectors.manage : L10n.Connectors.connect
    }
}

private extension ConnectorContent {
    var title: String {
        switch self {
        case .audio: L10n.Connectors.contentAudio
        case .transcript: L10n.Connectors.contentTranscript
        case .photos: L10n.Connectors.contentPhotos
        case .notes: L10n.Connectors.contentNotes
        }
    }

    var symbol: String {
        switch self {
        case .audio: "waveform"
        case .transcript: "text.alignleft"
        case .photos: "photo"
        case .notes: "square.and.pencil"
        }
    }
}

/// A small mark, the same size whichever kind of icon a connector brings.
private struct ConnectorIconView: View {
    let icon: ConnectorIcon
    @ScaledMetric private var size: CGFloat

    init(icon: ConnectorIcon, baseSize: CGFloat = 28) {
        self.icon = icon
        _size = ScaledMetric(wrappedValue: baseSize, relativeTo: .body)
    }

    var body: some View {
        Group {
            switch icon {
            case let .symbol(name):
                Image(systemName: name)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.dsSecondaryText)
            case let .image(url):
                if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
