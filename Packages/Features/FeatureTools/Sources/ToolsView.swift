import AppRouting
import DesignSystem
import Domain
import FeatureShared
import Localization
import SwiftUI
import UniformTypeIdentifiers

extension SummaryTemplate {
    static var blank: SummaryTemplate {
        SummaryTemplate(name: "", category: .general, instructions: "", sections: [TemplateSection(title: "")])
    }
}

/// A template as a file, for the share sheet.
struct TemplateFile: Transferable {
    let template: SummaryTemplate

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { try TemplateCodec.encode($0.template) }
            .suggestedFileName { "\($0.template.name).json" }
    }
}

struct TemplateDetailView: View {
    let templateID: String
    let center: SummaryCenter
    let recordings: () async -> [Recording]
    @State private var transcribed: [Recording] = []
    @State private var editing: SummaryTemplate?
    @State private var isConfirmingDelete = false
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    private var template: SummaryTemplate? {
        center.templates.first { $0.id == templateID }
    }

    var body: some View {
        if let template {
            content(template)
        }
    }

    private func content(_ template: SummaryTemplate) -> some View {
        List {
            if !template.instructions.isEmpty {
                Section(title: L10n.Templates.instructions) {
                    Text(template.instructions)
                }
                .listRowBackground(Color.clear)
            }
            Section(title: L10n.Templates.sections) {
                ForEach(Array(template.sections.enumerated()), id: \.offset) { _, section in
                    Label(
                        L10n.Summary.sectionTitle(section.title),
                        systemImage: section.kind == .tasks ? "checklist" : "list.bullet",
                    )
                }
            }
            .listRowBackground(Color.clear)
            if !transcribed.isEmpty {
                Section(title: L10n.Templates.tryOn) {
                    ForEach(transcribed.prefix(5)) { recording in
                        Button(recording.title) { run(template, on: recording) }
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .screenList()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.Summary.templateName(template.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { menu(template) }
        }
        .sheet(item: $editing) { draft in
            TemplateEditor(template: draft) { saved in
                Task { await center.save(saved) }
            }
        }
        .alert(L10n.Templates.delete, isPresented: $isConfirmingDelete) {
            Button(L10n.Library.delete, role: .destructive) {
                Task {
                    await center.delete(template)
                    dismiss()
                }
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        }
        .task { transcribed = await recordings() }
        .accessibilityIdentifier("screen.template")
    }

    private func menu(_ template: SummaryTemplate) -> some View {
        Menu {
            Button(L10n.Templates.setDefault, systemImage: "star") { center.setDefault(template) }
                .disabled(center.defaultTemplateID == template.id)
                .accessibilityIdentifier("template.default")
            if !template.isBuiltIn {
                Button(L10n.Templates.edit, systemImage: "pencil") { editing = template }
            }
            Button(L10n.Templates.duplicate, systemImage: "plus.square.on.square") {
                editing = SummaryTemplate(
                    name: L10n.Templates.copyName(L10n.Summary.templateName(template.name)),
                    category: template.category,
                    instructions: template.instructions,
                    sections: template.sections,
                )
            }
            .accessibilityIdentifier("template.duplicate")
            ShareLink(
                L10n.Summary.share,
                item: TemplateFile(template: template),
                preview: SharePreview(template.name),
            )
            if !template.isBuiltIn {
                Button(L10n.Library.delete, systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
            }
        } label: {
            Label(L10n.Library.more, systemImage: "ellipsis")
        }
        .accessibilityIdentifier("template.more")
    }

    private func run(_ template: SummaryTemplate, on recording: Recording) {
        Task {
            if await center.summarize(recording.id, template: template, language: nil) == .needsModel {
                router.push(.modelSettings)
            } else {
                router.push(.recording(recording.id, at: nil))
            }
        }
    }
}

struct TemplateEditor: View {
    @State var template: SummaryTemplate
    let onSave: (SummaryTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.Templates.name, text: $template.name)
                    .accessibilityIdentifier("template.name")
                Picker(L10n.Templates.categoryLabel, selection: $template.category) {
                    ForEach(TemplateCategory.allCases, id: \.self) {
                        Text(L10n.Templates.category($0.rawValue)).tag($0)
                    }
                }
                Section(L10n.Templates.instructions) {
                    TextField(L10n.Templates.instructionsHint, text: $template.instructions, axis: .vertical)
                        .lineLimit(3 ... 8)
                }
                Section(L10n.Templates.sections) {
                    ForEach($template.sections, id: \.self) { $section in
                        VStack(alignment: .leading) {
                            TextField(L10n.Templates.sectionTitle, text: $section.title)
                                .accessibilityIdentifier("template.section")
                            Picker(L10n.Templates.sectionKind, selection: $section.kind) {
                                Text(L10n.Templates.kindBullets).tag(SectionKind.bullets)
                                Text(L10n.Templates.kindTasks).tag(SectionKind.tasks)
                            }
                        }
                    }
                    .onDelete { template.sections.remove(atOffsets: $0) }
                    .onMove { template.sections.move(fromOffsets: $0, toOffset: $1) }
                    Button(L10n.Templates.addSection, systemImage: "plus") {
                        template.sections.append(TemplateSection(title: ""))
                    }
                    .disabled(template.sections.count >= TemplateCodec.Limits.sections)
                }
            }
            .navigationTitle(L10n.Templates.new)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save) {
                        onSave(template)
                        dismiss()
                    }
                    .disabled(!TemplateCodec.isValid(template))
                    .accessibilityIdentifier("template.save")
                }
            }
        }
    }
}

/// Describe it in plain words, and get a template to edit.
struct TemplateDraftSheet: View {
    let center: SummaryCenter
    let onDraft: (SummaryTemplate) -> Void
    @State private var description = ""
    @State private var isWorking = false
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.Templates.aiPrompt) {
                    TextField(L10n.Templates.aiHint, text: $description, axis: .vertical)
                        .lineLimit(4 ... 10)
                        .accessibilityIdentifier("template.ai.description")
                }
                if isWorking {
                    ProgressView()
                }
                if let failure {
                    Text(failure)
                        .foregroundStyle(Color.dsRecord)
                }
            }
            .navigationTitle(L10n.Templates.createWithAI)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Templates.aiGenerate, action: draft)
                        .disabled(isWorking || description.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("template.ai.generate")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func draft() {
        isWorking = true
        failure = nil
        Task {
            defer { isWorking = false }
            guard await center.hasLanguageModel else {
                failure = L10n.Templates.needsModel
                return
            }
            do {
                let template = try await center.draftTemplate(description: description)
                dismiss()
                onDraft(template)
            } catch {
                failure = L10n.Templates.aiFailed
            }
        }
    }
}
