import DesignSystem
import Domain
import Localization
import SwiftUI

/// Every model for one function, best first.
struct RoleModelsView: View {
    let role: ModelRole
    let controller: ModelsController
    @State private var showsAll = false

    var body: some View {
        Group {
            if let snapshot = controller.snapshot {
                list(snapshot)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(role.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.role")
    }

    private func list(_ snapshot: ModelsSnapshot) -> some View {
        let fits = snapshot.fits[role] ?? []
        let visible = showsAll ? fits : fits.filter { $0.label != .unsupported }
        return List {
            Section {
                Text(role.purpose)
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
                Picker(L10n.Models.mode, selection: Binding(
                    get: { snapshot.selections[role] ?? .automatic },
                    set: { controller.select($0, for: role) },
                )) {
                    Text(L10n.Models.automatic).tag(SelectionMode.automatic)
                    ForEach(fits.filter { snapshot.isInstalled($0.model.id) }) { fit in
                        Text(fit.model.displayName).tag(SelectionMode.pinned(fit.model.id))
                    }
                }
            }
            .listRowBackground(Color.clear)

            Section {
                ForEach(visible) { fit in
                    NavigationLink {
                        ModelDetailView(modelID: fit.model.id, role: role, controller: controller)
                    } label: {
                        ModelRow(fit: fit, state: snapshot.state(of: fit.model.id))
                    }
                    .accessibilityIdentifier("model.\(fit.model.id)")
                }
            }
            .listRowBackground(Color.clear)

            if fits.count != visible.count {
                Button(L10n.Models.showAll) { showsAll = true }
                    .listRowBackground(Color.clear)
            }
            if visible.count > 1 {
                NavigationLink {
                    CompareModelsView(role: role, fits: visible, snapshot: snapshot, controller: controller)
                } label: {
                    Text(L10n.Models.compare)
                }
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("models.compare")
            }
        }
        .screenList()
    }
}

/// The models for one function side by side, in the words used everywhere else.
struct CompareModelsView: View {
    let role: ModelRole
    let fits: [ModelFit]
    let snapshot: ModelsSnapshot
    let controller: ModelsController

    private var installed: [ModelFit] {
        fits.filter { snapshot.isInstalled($0.model.id) }
    }

    var body: some View {
        List {
            if role == .transcription, installed.count > 1 {
                trySection
            }
            ForEach(fits) { fit in
                Section(title: fit.model.displayName) {
                    LabeledContent(L10n.Models.fit, value: fit.reason.title)
                    LabeledContent(L10n.Models.speed, value: fit.speed.title)
                    if !fit.model.isSystemManaged {
                        LabeledContent(L10n.Models.size, value: fit.model.totalBytes.fileSize)
                    }
                    if !fit.model.languages.isEmpty {
                        LabeledContent(
                            L10n.Models.languages,
                            value: fit.model.languages.map(languageName).joined(separator: ", "),
                        )
                    }
                }
                .listRowBackground(Color.clear)
                .listSectionSeparator(.hidden, edges: .top)
            }
        }
        .screenList()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.Models.compare)
        .navigationBarTitleDisplayMode(.inline)
        .task { await controller.loadTrialChoices() }
        .onDisappear { controller.cancelSpeedTest() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.compareModels")
    }

    private var trySection: some View {
        Section(title: L10n.Models.tryTitle) {
            Text(L10n.Models.tryHint)
                .font(.dsMeta)
                .foregroundStyle(Color.dsSecondaryText)
            if controller.testing != nil {
                HStack(spacing: Spacing.small) {
                    ProgressView()
                    Text(L10n.Models.testing)
                }
            } else if controller.trialChoices.isEmpty {
                Text(L10n.Models.tryNoRecording)
                    .foregroundStyle(Color.dsSecondaryText)
            } else {
                Picker(L10n.Models.tryRecording, selection: Binding(
                    get: { controller.trialRecording },
                    set: { controller.trialRecording = $0 },
                )) {
                    ForEach(controller.trialChoices) { recording in
                        Text(choiceTitle(recording)).tag(Optional(recording.id))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("models.tryRecording")
                Button(L10n.Models.tryRun) { controller.runTrial(installed.prefix(2).map(\.model.id)) }
                    .secondaryAction(.regular)
                    .accessibilityIdentifier("models.try")
            }
            if let error = controller.testError {
                Text(error)
                    .foregroundStyle(Color.dsRecord)
            }
            ForEach(controller.trials) { trial in
                VStack(alignment: .leading, spacing: Spacing.small) {
                    RowLabel(name(of: trial), detail: L10n.Models.tryTime(Int(trial.seconds.rounded())))
                    Text(trial.text)
                        .font(.dsMeta)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("models.trialText")
                    Button(L10n.Models.tryUse) { controller.select(.pinned(trial.modelID), for: role) }
                        .secondaryAction(.small)
                        .accessibilityIdentifier("models.tryUse")
                }
            }
        }
        .listRowBackground(Color.clear)
        .listSectionSeparator(.hidden, edges: .top)
    }

    private func choiceTitle(_ recording: Recording) -> String {
        let day = recording.createdAt.formatted(date: .abbreviated, time: .omitted)
        return "\(recording.title) · \(day)"
    }

    private func name(of trial: ModelTrial) -> String {
        fits.first { $0.model.id == trial.modelID }?.model.displayName ?? trial.modelID
    }
}

struct ModelRow: View {
    let fit: ModelFit
    let state: InstallState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack {
                Text(fit.model.displayName)
                if fit.label == .best {
                    Text(fit.label.title)
                        .font(.dsBadge)
                        .foregroundStyle(Color.dsAction)
                }
            }
            Text(detail)
                .font(.dsMeta)
                .foregroundStyle(Color.dsSecondaryText)
            if let progress = state.progress {
                ProgressView(value: progress)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if fit.model.isSystemManaged {
            parts.append(L10n.Models.managedByIOS)
        } else {
            parts.append(fit.model.totalBytes.fileSize)
        }
        parts.append(state.title ?? fit.label.title)
        return parts.joined(separator: " · ")
    }
}

extension InstallState {
    var progress: Double? {
        switch self {
        case let .downloading(received, total), let .paused(received, total):
            total > 0 ? Double(received) / Double(total) : 0
        default: nil
        }
    }

    var title: String? {
        switch self {
        case .notInstalled: nil
        case .queued: L10n.Models.stateQueued
        case let .downloading(received, total):
            L10n.Models.stateDownloading(received.fileSize, total.fileSize)
        case .paused: L10n.Models.statePaused
        case .waitingForWiFi: L10n.Models.stateWaitingWiFi
        case .verifying: L10n.Models.stateVerifying
        case .preparing: L10n.Models.statePreparing
        case .selfTest: L10n.Models.stateTesting
        case .ready: L10n.Models.stateReady
        case let .failed(reason):
            switch reason {
            case .noSpace: L10n.Models.failedSpace
            case .damaged: L10n.Models.failedDamaged
            case .unavailable: L10n.Models.failedUnavailable
            case .prepareFailed: L10n.Models.failedPrepare
            }
        }
    }
}
