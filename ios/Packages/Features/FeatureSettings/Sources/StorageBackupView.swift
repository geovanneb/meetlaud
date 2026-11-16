import DesignSystem
import Domain
import Localization
import SwiftUI

public struct StorageBackupView: View {
    private let controller: SystemController
    @State private var isExporting = false
    @State private var isRestoring = false

    public init(controller: SystemController) {
        self.controller = controller
    }

    public var body: some View {
        List {
            Section(title: L10n.System.usage) {
                if let usage = controller.usage {
                    usageSummary(usage)
                    Button(action: controller.clearCache) {
                        ActionRow(title: L10n.System.clearCache)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("storage.clearCache")
                } else {
                    // Measuring a large library takes a moment. The bar stays in place, moving, so the screen
                    // does not jump when the numbers arrive.
                    ActivityBar(fraction: nil)
                        .padding(.vertical, Spacing.medium)
                }
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)

            Section {
                Toggle(L10n.System.iosBackup, isOn: Binding(
                    get: { controller.isBackupIncluded },
                    set: { controller.setBackupIncluded($0) },
                ))
                .accessibilityIdentifier("storage.backup")
                // A row, not a footer: plain list footers float over the rows and fail the contrast audit.
                Text(L10n.System.iosBackupNote)
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
            } header: {
                SectionHeader(L10n.System.backup)
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)

            Section {
                Button { isExporting = true } label: {
                    ActionRow(title: L10n.System.exportLibrary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("storage.export")
                Button { isRestoring = true } label: {
                    ActionRow(title: L10n.System.importLibrary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("storage.import")
                // A row, not a footer: plain list footers float over the rows and fail the contrast audit.
                Text(L10n.System.moveLibraryNote)
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
            } header: {
                SectionHeader(L10n.System.moveLibrary)
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)
        }
        .screenList()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.System.storageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { controller.refreshUsage() }
        .sheet(isPresented: $isExporting, onDismiss: controller.resetArchive) {
            ExportLibrarySheet(controller: controller)
        }
        .sheet(isPresented: $isRestoring, onDismiss: controller.resetArchive) {
            RestoreLibrarySheet(controller: controller)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.storage")
    }

    /// What the app takes, as parts of one bar, and what is still free on the device.
    private func usageSummary(_ usage: StorageUsage) -> some View {
        let parts = [
            UsagePart(
                id: "recordings",
                title: L10n.System.usageRecordings,
                value: usage.recordings,
                formatted: usage.recordings.fileSize,
            ),
            UsagePart(
                id: "models",
                title: L10n.System.usageModels,
                value: usage.models,
                formatted: usage.models.fileSize,
            ),
            UsagePart(
                id: "library",
                title: L10n.System.usageLibrary,
                value: usage.library,
                formatted: usage.library.fileSize,
            ),
            UsagePart(id: "cache", title: L10n.System.usageCache, value: usage.cache, formatted: usage.cache.fileSize),
        ]
        return VStack(alignment: .leading, spacing: Spacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.System.usageInUse(usage.total.fileSize))
                    .font(.dsHeading)
                    .foregroundStyle(Color.dsPrimaryText)
                Spacer(minLength: Spacing.small)
            }
            // The whole bar is the app's share next to what is free, when iOS says, so "how full" is visible.
            UsageBar(parts: parts, total: usage.available.map { usage.total + $0 })
            if let available = usage.available {
                LabeledContent(L10n.System.usageFree, value: available.fileSize)
                    .font(.dsMeta)
                    .foregroundStyle(Color.dsSecondaryText)
            }
        }
        .padding(.vertical, Spacing.small)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("storage.usage")
    }
}

/// Takes the whole row, so that the tap target and the text can both grow with Dynamic Type.
private struct ActionRow: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 0)
        }
        .tappableTarget()
    }
}

private struct ArchiveStatus: View {
    let outcome: SystemController.ArchiveOutcome

    var body: some View {
        switch outcome {
        case let .working(fraction):
            HStack(spacing: Spacing.compact) {
                ActivityBar(fraction: fraction)
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.dsMeta.monospacedDigit())
                    .foregroundStyle(Color.dsPrimaryText)
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("archive.progress")
        case let .failed(reason):
            Text(message(reason))
                .foregroundStyle(Color.dsRecord)
                .accessibilityIdentifier("archive.error")
        case .restored:
            Text(L10n.System.restoreDone)
                .accessibilityIdentifier("archive.restored")
        case .idle, .exported:
            EmptyView()
        }
    }

    private func message(_ reason: SystemController.ArchiveFailureReason) -> String {
        switch reason {
        case .recording: L10n.System.errorRecording
        case .wrongPassword: L10n.System.errorPassword
        case .damaged: L10n.System.errorDamaged
        case .incompatible: L10n.System.errorIncompatible
        case .other: L10n.System.errorOther
        }
    }
}

private struct ExportLibrarySheet: View {
    let controller: SystemController
    @State private var password = ""
    @State private var repeated = ""
    @State private var includesVoicePrints = false
    @Environment(\.dismiss) private var dismiss

    private static let minimumLength = 8

    private var isValid: Bool {
        password.count >= Self.minimumLength && password == repeated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(L10n.System.password, text: $password)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("archive.password")
                    SecureField(L10n.System.passwordRepeat, text: $repeated)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("archive.passwordRepeat")
                } footer: {
                    Text(L10n.System.passwordNote(Self.minimumLength))
                }
                Section {
                    Toggle(L10n.System.includeVoicePrints, isOn: $includesVoicePrints)
                } footer: {
                    Text(L10n.System.includeVoicePrintsNote)
                }
                Section {
                    if case let .exported(url) = controller.archive {
                        ShareLink(item: url) {
                            Label(L10n.System.saveFile, systemImage: "square.and.arrow.up")
                                .foregroundStyle(Color.dsPrimaryText)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("archive.share")
                    } else {
                        Button(L10n.System.createFile) {
                            Task {
                                await controller.exportLibrary(
                                    password: password, includingVoicePrints: includesVoicePrints,
                                )
                            }
                        }
                        .disabled(!isValid || isWorking)
                        .accessibilityIdentifier("archive.create")
                    }
                    ArchiveStatus(outcome: controller.archive)
                }
            }
            .navigationTitle(L10n.System.exportLibrary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.done) { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private var isWorking: Bool {
        if case .working = controller.archive {
            true
        } else {
            false
        }
    }
}

private struct RestoreLibrarySheet: View {
    let controller: SystemController
    @State private var file: URL?
    @State private var isPicking = false
    @State private var password = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button(file?.lastPathComponent ?? L10n.System.chooseFile) { isPicking = true }
                        .accessibilityIdentifier("archive.choose")
                    SecureField(L10n.System.password, text: $password)
                        .accessibilityIdentifier("archive.password")
                } footer: {
                    Text(L10n.System.restoreWarning)
                }
                Section {
                    Button(L10n.System.restore, role: .destructive) {
                        guard let file else { return }
                        Task { await controller.restoreLibrary(from: file, password: password) }
                    }
                    .disabled(file == nil || password.isEmpty)
                    .accessibilityIdentifier("archive.restore")
                    ArchiveStatus(outcome: controller.archive)
                }
            }
            .navigationTitle(L10n.System.importLibrary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.done) { dismiss() }
                }
            }
            .fileImporter(isPresented: $isPicking, allowedContentTypes: [.data]) { result in
                file = try? result.get()
            }
        }
    }
}
