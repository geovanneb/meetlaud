import Domain
import FeatureShared
import Foundation
import Localization

extension DetailModel {
    /// Coming from a search result or a link means someone wants a specific moment, so that stays on the transcript.
    var opensOnSummary: Bool {
        startTime == nil && !summaries.isEmpty
    }

    var audioFile: URL {
        files.audioFile(for: id)
    }

    func exportedTranscript(format: TranscriptFormat, options: ExportOptions) -> String {
        TranscriptExporter.text(
            title: recording?.title ?? "", segments: segments, speakers: speakers, format: format, options: options,
        )
    }

    func exportedSummary() -> String {
        guard let selectedSummary else { return "" }
        return SummaryExporter.markdown(title: recording?.title ?? "", summary: selectedSummary, speakers: speakers)
    }

    var selectedSummary: Summary? {
        summaries.first { $0.id == selectedSummaryID } ?? summaries.last
    }

    var templates: [SummaryTemplate] {
        summaryCenter.templates
    }

    var defaultTemplate: SummaryTemplate {
        summaryCenter.defaultTemplate
    }

    func template(for summary: Summary) -> SummaryTemplate? {
        templates.first { $0.name == summary.templateName }
    }

    /// Changes when a step ends, and stays the same while text streams in.
    var summarySteps: [UUID: Double] {
        summaryCenter.progress.mapValues(\.fraction)
    }

    func progress(of summary: Summary) -> SummaryProgress? {
        summaryCenter.progress[summary.id]
    }

    func refreshSummaries() async {
        summaries = await summaryCenter.summaries(for: id)
        if selectedSummaryID == nil || !summaries.contains(where: { $0.id == selectedSummaryID }) {
            selectedSummaryID = summaries.last?.id
        }
        await summaryCenter.reloadTemplates()
    }

    func summarize(template: SummaryTemplate, language: String?) async -> TranscribeOutcome {
        let outcome = await summaryCenter.summarize(id, template: template, language: language)
        await refreshSummaries()
        selectedSummaryID = summaries.last?.id
        return outcome
    }

    func cancel(_ summary: Summary) async {
        await summaryCenter.cancel(summary.id)
        await refreshSummaries()
    }

    func deleteSelectedSummary() async {
        guard let summary = selectedSummary else { return }
        if summaryCenter.progress[summary.id] != nil {
            await summaryCenter.cancel(summary.id)
        } else {
            await summaryCenter.delete(summary)
        }
        selectedSummaryID = nil
        await refreshSummaries()
    }

    func toggle(_ item: SummaryItem, in summary: Summary) async {
        var updated = summary
        for section in updated.sections.indices {
            for index in updated.sections[section].items.indices
                where updated.sections[section].items[index].id == item.id
            {
                updated.sections[section].items[index].isDone.toggle()
            }
        }
        await summaryCenter.save(updated)
        await refreshSummaries()
    }

    /// Text with speakers as they are named right now, so that renaming needs no new summary.
    func display(_ text: String) -> String {
        SpeakerTokens.decode(text, speakers: speakers) { [self] in name(of: $0) }
    }

    func detail(of item: SummaryItem) -> String? {
        let parts = [item.owner.map(display), item.due].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var openTasks: [SummaryItem] {
        (selectedSummary?.sections ?? []).filter { $0.kind == .tasks }.flatMap(\.items).filter { !$0.isDone }
    }

    /// False when Reminders access is off.
    func sendTasksToReminders() async -> Bool {
        let source = recording?.title
        for task in openTasks {
            let notes = [detail(of: task), source].compactMap(\.self).joined(separator: "\n")
            do {
                try await reminders.add(title: display(task.text), notes: notes)
            } catch {
                return false
            }
        }
        return true
    }

    func plainText(of summary: Summary) -> String {
        var lines = [recording?.title ?? ""]
        for section in summary.sections {
            lines.append("\n\(L10n.Summary.sectionTitle(section.title))")
            for item in section.items {
                let detail = detail(of: item).map { " (\($0))" } ?? ""
                lines.append("- \(display(item.text))\(detail)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
