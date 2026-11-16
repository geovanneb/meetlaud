import DesignSystem
import Domain
import Localization
import SwiftUI

/// One place for every model on the device, and the current advice about them.
public struct AIModelsView: View {
    private let controller: ModelsController

    public init(controller: ModelsController) {
        self.controller = controller
    }

    public var body: some View {
        Group {
            if let snapshot = controller.snapshot {
                content(snapshot)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.Models.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.models")
    }

    private func content(_ snapshot: ModelsSnapshot) -> some View {
        List {
            Section {
                DeviceCard(snapshot: snapshot)
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)
            .listRowSeparator(.hidden)
            // Above anything that depends on it: a choice must not move the control it was made on.
            priority(snapshot)
            suggestions(snapshot)
            Section(title: L10n.Models.functions) {
                ForEach(ModelRole.allCases, id: \.self) { role in
                    RoleRow(role: role, snapshot: snapshot, controller: controller)
                }
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)
            Section {
                NavigationLink {
                    StorageView(controller: controller)
                } label: {
                    Text(L10n.Models.storage)
                }
                .accessibilityIdentifier("models.storage")
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)
        }
        .screenList()
        .motion(Motion.standard, value: snapshot.suggestions.map(\.id))
        .motion(Motion.standard, value: snapshot.missingFromSetup.isEmpty)
        .motion(Motion.standard, value: snapshot.setupProgress == nil)
    }

    @ViewBuilder
    private func suggestions(_ snapshot: ModelsSnapshot) -> some View {
        if !snapshot.suggestions.isEmpty {
            Section(title: L10n.Models.suggestions) {
                ForEach(snapshot.suggestions) { suggestion in
                    Text(suggestion.title(in: snapshot))
                        .font(.dsMeta)
                        .swipeActions {
                            Button(L10n.Models.dismiss) { controller.dismiss(suggestion) }
                        }
                }
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)
        }
        // While the setup is on its way, its progress takes the place of the button that started it.
        if let progress = snapshot.setupProgress {
            Section {
                SetupProgressRow(progress: progress)
                if progress.phase == .paused {
                    Button(L10n.Models.resumeAll) { controller.resumeSetup() }
                        .foregroundStyle(Color.dsAction)
                        .accessibilityIdentifier("models.resumeAll")
                }
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)
        } else if !snapshot.missingFromSetup.isEmpty {
            Section {
                Button(L10n.Models.downloadAll) { controller.installRecommended() }
                    .foregroundStyle(Color.dsAction)
                    .accessibilityIdentifier("models.downloadAll")
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)
        }
    }

    private func priority(_ snapshot: ModelsSnapshot) -> some View {
        Section(title: L10n.Models.priority) {
            PriorityPicker(initial: snapshot.priority, onChange: controller.setPriority)
        }
        .listRowBackground(Color.clear)
        .listSectionSeparator(.hidden, edges: .top)
    }
}

/// The one-tap setup as one line, so a download in the background is never a silent one.
private struct SetupProgressRow: View {
    let progress: SetupProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(title)
                .font(.dsMeta)
            // The shared bar, as on each model's row. Checking and preparing have no fraction, so it keeps moving.
            ActivityBar(fraction: progress.phase == .finishing ? nil : progress.fraction)
                .padding(.top, Spacing.xSmall)
                .accessibilityHidden(true)
            if progress.phase == .downloading {
                Text(L10n.Models.setupBackground)
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(progress.fraction.formatted(.percent.precision(.fractionLength(0))))
        .accessibilityIdentifier("models.setupProgress")
    }

    private var title: String {
        let received = progress.received.fileSize
        let total = progress.total.fileSize
        return switch progress.phase {
        case .downloading: L10n.Models.setupDownloading(received, total)
        case .paused: L10n.Models.setupPaused(received, total)
        case .waitingForWiFi: L10n.Models.stateWaitingWiFi
        case .finishing: L10n.Models.setupFinishing
        }
    }
}

/// Holds its own selection. The saved value comes back later through a new snapshot, and a control bound directly to
/// it would snap back to the old segment first, which breaks the system's sliding animation.
private struct PriorityPicker: View {
    let onChange: (Priority) -> Void
    @State private var selection: Priority

    init(initial: Priority, onChange: @escaping (Priority) -> Void) {
        self.onChange = onChange
        _selection = State(initialValue: initial)
    }

    var body: some View {
        Picker(L10n.Models.priority, selection: $selection) {
            ForEach(Priority.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: selection) { _, priority in onChange(priority) }
    }
}

private struct DeviceCard: View {
    let snapshot: ModelsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(snapshot.device.name)
                .font(.dsHeading)
            HStack(spacing: Spacing.small) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(snapshot.rightNow.title)
                    .font(.dsMeta)
                    .accessibilityIdentifier("models.rightNow")
            }
            if let detail = snapshot.rightNow.detail {
                Text(detail)
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
            }
            Text(summary)
                .font(.dsMeta)
                .foregroundStyle(Color.dsSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .background(Color.dsSurface, in: .rect(cornerRadius: Radius.medium))
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch snapshot.rightNow {
        case .great, .good: .dsAction
        case .limited, .paused: .dsRecord
        }
    }

    private var summary: String {
        let memory = Int64(snapshot.device.physicalMemoryMB) * 1_000_000
        return L10n.Models.deviceSummary(memory.fileSize, snapshot.condition.freeBytes.fileSize)
    }
}

private struct RoleRow: View {
    let role: ModelRole
    let snapshot: ModelsSnapshot
    let controller: ModelsController

    private var fits: [ModelFit] {
        snapshot.fits[role] ?? []
    }

    var body: some View {
        if fits.isEmpty {
            RowLabel(role.title, detail: L10n.Models.comingLater)
                // One thing to VoiceOver: the function and its state.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([role.title, L10n.Models.comingLater].formatted(.list(type: .and, width: .narrow)))
                .accessibilityIdentifier("models.role.\(role.rawValue)")
        } else {
            NavigationLink {
                RoleModelsView(role: role, controller: controller)
            } label: {
                RowLabel(role.title, detail: detail)
            }
            .accessibilityIdentifier("models.role.\(role.rawValue)")
        }
    }

    private var detail: String {
        if case let .pinned(id) = snapshot.selections[role], let fit = fits.first(where: { $0.model.id == id }) {
            let state = snapshot.state(of: id)
            guard state.isInFlight, let title = state.title else { return fit.model.displayName }
            return [fit.model.displayName, title].joined(separator: " · ")
        }
        let installed = fits.first { snapshot.isInstalled($0.model.id) }
        if installed == nil,
           let coming = fits.first(where: { snapshot.state(of: $0.model.id).isInFlight }),
           let state = snapshot.state(of: coming.model.id).title
        {
            return state
        }
        return installed.map { L10n.Models.automaticUsing($0.model.displayName) } ?? L10n.Models.notInstalled
    }
}
