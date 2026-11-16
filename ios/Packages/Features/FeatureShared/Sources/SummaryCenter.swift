import Domain
import Foundation
import Observation

/// Starts summaries and holds templates, from any screen. There is one for the life of the app.
@MainActor
@Observable
public final class SummaryCenter {
    public private(set) var progress: [UUID: SummaryProgress] = [:]
    public private(set) var userTemplates: [SummaryTemplate] = []
    public private(set) var defaultTemplateID: String

    @ObservationIgnored private let coordinator: SummaryCoordinator
    @ObservationIgnored private let manager: ModelManager
    @ObservationIgnored private let store: any SummaryStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(
        coordinator: SummaryCoordinator,
        manager: ModelManager,
        store: any SummaryStore,
        defaults: UserDefaults = .standard,
    ) {
        self.coordinator = coordinator
        self.manager = manager
        self.store = store
        self.defaults = defaults
        defaultTemplateID = defaults.string(forKey: SummaryPreferences.defaultTemplateKey) ?? BuiltInTemplates.defaultID
        task = Task { [weak self] in
            for await progress in coordinator.updates {
                self?.progress = progress
            }
        }
    }

    deinit {
        task?.cancel()
    }

    public var templates: [SummaryTemplate] {
        BuiltInTemplates.all + userTemplates
    }

    public var defaultTemplate: SummaryTemplate {
        templates.first { $0.id == defaultTemplateID } ?? BuiltInTemplates.all[0]
    }

    public func setDefault(_ template: SummaryTemplate) {
        defaultTemplateID = template.id
        defaults.set(template.id, forKey: SummaryPreferences.defaultTemplateKey)
    }

    public func reloadTemplates() async {
        userTemplates = await (try? store.userTemplates()) ?? []
    }

    public func save(_ template: SummaryTemplate) async {
        try? await store.save(template)
        await reloadTemplates()
    }

    public func delete(_ template: SummaryTemplate) async {
        try? await store.deleteTemplate(template.id)
        await reloadTemplates()
    }

    public func importTemplate(from data: Data) async throws -> SummaryTemplate {
        let template = try TemplateCodec.decode(data)
        await save(template)
        return template
    }

    public var hasLanguageModel: Bool {
        get async { await manager.model(for: .chat, language: nil) != nil }
    }

    public func draftTemplate(description: String) async throws -> SummaryTemplate {
        guard let model = await manager.model(for: .chat, language: nil) else { throw TemplateError.invalid }
        return try await coordinator.draftTemplate(
            description: description, modelID: model.id, language: Locale.current.language.languageCode?.identifier,
        )
    }

    public func summarize(_ id: RecordingID, template: SummaryTemplate, language: String?) async -> TranscribeOutcome {
        guard let model = await manager.model(for: .chat, language: language) else { return .needsModel }
        _ = try? await coordinator.enqueue(id, template: template, modelID: model.id, language: language)
        return .started
    }

    public func cancel(_ id: UUID) async {
        try? await coordinator.cancel(id)
    }

    public func summaries(for id: RecordingID) async -> [Summary] {
        await (try? store.summaries(for: id)) ?? []
    }

    public func save(_ summary: Summary) async {
        try? await store.save(summary)
    }

    public func delete(_ summary: Summary) async {
        try? await store.deleteSummary(summary.id)
    }
}
