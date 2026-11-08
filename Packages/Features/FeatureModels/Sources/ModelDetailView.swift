import DesignSystem
import Domain
import Localization
import SwiftUI

struct ModelDetailView: View {
    let modelID: String
    let role: ModelRole
    let controller: ModelsController
    @State private var isConfirmingDelete = false
    @State private var isConfirmingCellular = false

    private var fit: ModelFit? {
        controller.snapshot?.fits[role]?.first { $0.model.id == modelID }
    }

    private var state: InstallState {
        controller.snapshot?.state(of: modelID) ?? .notInstalled
    }

    var body: some View {
        Group {
            if let fit {
                list(fit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(fit?.model.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.modelDetail")
    }

    private func list(_ fit: ModelFit) -> some View {
        List {
            Section {
                labeled(L10n.Models.fit, fit.reason.title)
                labeled(L10n.Models.speed, fit.speed.title)
                if !fit.model.isSystemManaged {
                    labeled(L10n.Models.size, fit.model.totalBytes.fileSize)
                }
                if !fit.model.languages.isEmpty {
                    labeled(L10n.Models.languages, fit.model.languages.map(languageName).joined(separator: ", "))
                }
                labeled(L10n.Models.license, fit.model.license)
                if fit.model.qualityIsProvisional {
                    Text(L10n.Models.qualityProvisional)
                        .font(.dsMeta)
                        .foregroundStyle(Color.dsSecondaryText)
                }
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)

            Section {
                actions(fit)
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)

            // Speakers have no clip to run yet.
            if state == .ready, fit.model.roles.contains(.transcription) {
                speedTest
                if !controller.history.isEmpty {
                    history
                }
            } else if state == .ready, fit.model.roles.contains(.chat) {
                languageTest
            } else if state == .ready, fit.model.roles.contains(.search) {
                SearchTestSection(controller: controller, modelID: modelID)
            }
        }
        .screenList()
        .task(id: controller.lastTest) { await controller.loadHistory(modelID) }
        .confirmationDialog(L10n.Models.deleteConfirm, isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button(L10n.Library.delete, role: .destructive) { controller.remove(modelID) }
            Button(L10n.Common.cancel, role: .cancel) {}
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(title)
                .font(.dsMeta)
                .foregroundStyle(Color.dsSecondaryText)
            Text(value)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actions(_ fit: ModelFit) -> some View {
        if let title = state.title {
            HStack(spacing: Spacing.small) {
                if state.isWorking {
                    ProgressRing(fraction: state.progress)
                }
                Text(title)
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("model.state")
        }
        if state.isWorking {
            ActivityBar(fraction: state.progress)
        }
        switch state {
        case .notInstalled, .failed:
            if fit.label != .unsupported {
                Button(fit.model.isSystemManaged ? L10n.Models.install : L10n.Models.download) {
                    controller.install(fit.model)
                }
                .foregroundStyle(Color.dsAction)
                .accessibilityIdentifier("model.download")
            }
        case .downloading, .queued, .waitingForWiFi:
            Button(L10n.Recorder.pause) { controller.pause(modelID) }
            Button(L10n.Common.cancel, role: .destructive) { controller.cancel(modelID) }
        case .paused:
            Button(L10n.Recorder.resume) { controller.install(fit.model) }
            Button(L10n.Common.cancel, role: .destructive) { controller.cancel(modelID) }
        case .ready:
            if !fit.model.isSystemManaged {
                Button(L10n.Library.delete, role: .destructive) { isConfirmingDelete = true }
                    .accessibilityIdentifier("model.delete")
            }
        case .verifying, .preparing, .selfTest:
            EmptyView()
        }
    }

    private var languageTest: some View {
        Section(title: L10n.Models.speedTest) {
            if controller.testing == modelID {
                HStack(spacing: Spacing.small) {
                    ProgressView()
                    Text(L10n.Models.testing)
                }
                Button(L10n.Common.cancel) { controller.cancelSpeedTest() }
            } else {
                Button(L10n.Models.quickTest) { controller.runLanguageTest(modelID) }
                    .disabled(controller.testing != nil)
                    .accessibilityIdentifier("model.quickTest")
            }
            if let error = controller.testError {
                Text(error)
                    .foregroundStyle(Color.dsRecord)
                    .accessibilityIdentifier("model.testError")
            }
            if let result = controller.lastLanguageTest, result.modelID == modelID {
                Text(L10n.Models.writingSpeed(result.wordsPerMinute))
                    .accessibilityIdentifier("model.testResult")
            }
        }
        .listRowBackground(Color.clear)
        .listSectionSeparator(.hidden, edges: .top)
    }

    private var history: some View {
        Section(title: L10n.Models.history) {
            ForEach(controller.history, id: \.self) { run in
                RowLabel(
                    run.outcome == .killed ? L10n.Models.runStopped : SpeedEvidence.measured(run.speedX).title,
                    detail: run.date.formatted(date: .abbreviated, time: .shortened),
                )
            }
        }
        .listRowBackground(Color.clear)
        .listSectionSeparator(.hidden, edges: .top)
        .accessibilityIdentifier("model.history")
    }

    private var speedTest: some View {
        Section(title: L10n.Models.speedTest) {
            if controller.testing == modelID {
                HStack(spacing: Spacing.small) {
                    ProgressView()
                    Text(L10n.Models.testing)
                }
                Button(L10n.Common.cancel) { controller.cancelSpeedTest() }
            } else {
                Button(L10n.Models.quickTest) { controller.runSpeedTest(modelID, sustained: false) }
                    .disabled(controller.testing != nil)
                    .accessibilityIdentifier("model.quickTest")
                Button(L10n.Models.sustainedTest) { controller.runSpeedTest(modelID, sustained: true) }
                    .disabled(controller.testing != nil)
                Text(L10n.Models.sustainedHint)
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
            }
            if let error = controller.testError {
                Text(error)
                    .foregroundStyle(Color.dsRecord)
                    .accessibilityIdentifier("model.testError")
            }
            if let result = controller.lastTest, result.modelID == modelID {
                Text(SpeedEvidence.measured(result.speedX).title)
                    .accessibilityIdentifier("model.testResult")
            }
        }
        .listRowBackground(Color.clear)
        .listSectionSeparator(.hidden, edges: .top)
    }
}
