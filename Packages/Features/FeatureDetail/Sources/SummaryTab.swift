import AppRouting
import DesignSystem
import Domain
import FeatureShared
import Localization
import SwiftUI

struct SummaryTab: View {
    let model: DetailModel
    let onOpenTranscript: () -> Void
    @State private var isChoosing = false
    @State private var isShowingMap = false
    @State private var isConfirmingDelete = false
    @State private var isConfirmingReminders = false
    @State private var reminderMessage: String?
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionShape

    var body: some View {
        Group {
            if model.segments.isEmpty {
                prompt(message: L10n.Summary.needsTranscript) {
                    Button(L10n.Summary.openTranscript, action: onOpenTranscript)
                        .primaryAction()
                }
            } else if model.summaries.isEmpty {
                prompt(message: L10n.Summary.emptyMessage) {
                    Button(L10n.Summary.generate) { generate(model.defaultTemplate, language: nil) }
                        .primaryAction()
                        .accessibilityIdentifier("summary.generate")
                    Button(L10n.Summary.choose) { isChoosing = true }
                        .accessibilityIdentifier("summary.choose")
                }
            } else {
                VStack(spacing: 0) {
                    tabs
                    if let summary = model.selectedSummary {
                        SummaryDocument(model: model, summary: summary)
                    }
                }
            }
        }
        .sheet(isPresented: $isChoosing) {
            NewSummarySheet(templates: model.templates, selected: model.defaultTemplate, onGenerate: generate)
        }
        .sheet(isPresented: $isShowingMap) {
            if let summary = model.selectedSummary {
                MindMapView(
                    model: model,
                    root: .tree(title: model.recording?.title ?? "", summary: summary),
                )
            }
        }
        .alert(
            model.selectedSummary.map { _ in L10n.Summary.deleteConfirm } ?? "",
            isPresented: $isConfirmingDelete,
        ) {
            Button(L10n.Library.delete, role: .destructive) {
                Task { await model.deleteSelectedSummary() }
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        }
        .alert(L10n.Summary.toReminders, isPresented: $isConfirmingReminders) {
            Button(L10n.Summary.toReminders) { sendTasks() }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.Summary.toRemindersConfirm(model.openTasks.count))
        }
        .alert(
            reminderMessage ?? "",
            isPresented: Binding(get: { reminderMessage != nil }, set: {
                if !$0 {
                    reminderMessage = nil
                }
            }),
        ) {
            Button(L10n.Common.ok) {}
        }
    }

    private func generate(_ template: SummaryTemplate, language: String?) {
        Task {
            if await model.summarize(template: template, language: language) == .needsModel {
                router.push(.modelSettings)
            }
        }
    }

    private func sendTasks() {
        Task {
            reminderMessage = await model.sendTasksToReminders()
                ? L10n.Summary.remindersAdded
                : L10n.Summary.remindersDenied
        }
    }

    private func prompt(message: String, @ViewBuilder actions: () -> some View) -> some View {
        VStack(spacing: Spacing.medium) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.dsSecondaryText)
            actions()
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity)
        .fillsTab()
    }

    // MARK: - Tabs

    private var tabs: some View {
        HStack(spacing: Spacing.xSmall) {
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.xSmall) {
                    ForEach(model.summaries) { summary in
                        tab(for: summary)
                    }
                }
            }
            .scrollIndicators(.hidden)
            Button {
                isChoosing = true
            } label: {
                Label(L10n.Summary.add, systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .tappableTarget()
            }
            .accessibilityIdentifier("summary.add")
            if let summary = model.selectedSummary {
                moreMenu(summary)
            }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.bottom, Spacing.xSmall)
    }

    private func tab(for summary: Summary) -> some View {
        let isSelected = summary.id == model.selectedSummaryID
        return Button {
            withAnimation(reduceMotion ? nil : Motion.quick) { model.selectedSummaryID = summary.id }
        } label: {
            // One weight in both states, so that the tabs around it keep their place.
            Text(L10n.Summary.templateName(summary.templateName))
                .font(.dsMeta)
                .foregroundStyle(isSelected ? Color.dsPrimaryText : Color.dsSecondaryText)
                .padding(.horizontal, Spacing.compact)
                .tappableTarget()
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.dsSelection)
                            .padding(.vertical, Spacing.xSmall)
                            .matchedGeometryEffect(id: "selection", in: selectionShape)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("summary.tab")
    }

    private func moreMenu(_ summary: Summary) -> some View {
        Menu {
            Button(L10n.Summary.mindMap, systemImage: "point.3.connected.trianglepath.dotted") { isShowingMap = true }
                .accessibilityIdentifier("summary.mindMap")
            ShareLink(L10n.Summary.share, item: model.plainText(of: summary))
            if !model.openTasks.isEmpty {
                Button(L10n.Summary.toReminders, systemImage: "checklist") { isConfirmingReminders = true }
                    .accessibilityIdentifier("summary.reminders")
            }
            Button(L10n.Summary.regenerate, systemImage: "arrow.clockwise") {
                if let template = model.template(for: summary) {
                    generate(template, language: summary.language)
                } else {
                    isChoosing = true
                }
            }
            Button(L10n.Summary.delete, systemImage: "trash", role: .destructive) {
                isConfirmingDelete = true
            }
        } label: {
            Label(L10n.Library.more, systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .tappableTarget()
        }
        .accessibilityIdentifier("summary.more")
    }
}
