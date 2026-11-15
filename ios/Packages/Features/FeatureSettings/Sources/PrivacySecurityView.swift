import AppRouting
import DesignSystem
import Domain
import FeatureShared
import Localization
import SwiftUI

public struct PrivacySecurityView: View {
    private let controller: SystemController
    private let lock: AppLockController
    @State private var isErasing = false
    @AppStorage(SpotlightPreferences.key) private var showsInSpotlight = false

    public init(controller: SystemController, lock: AppLockController) {
        self.controller = controller
        self.lock = lock
    }

    public var body: some View {
        List {
            Section {
                Toggle(L10n.System.appLock, isOn: Binding(
                    get: { lock.state.isEnabled },
                    set: { value in Task { _ = await lock.setEnabled(value) } },
                ))
                .disabled(!lock.canLock)
                .accessibilityIdentifier("privacy.lock")
            } header: {
                SectionHeader(L10n.System.security)
            } footer: {
                Text(lock.canLock ? L10n.System.appLockNote : L10n.System.appLockUnavailable)
                    .foregroundStyle(Color.dsSecondaryText)
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)

            Section {
                Toggle(L10n.System.spotlight, isOn: $showsInSpotlight)
                    .accessibilityIdentifier("privacy.spotlight")
                // A row, not a footer: it has to be read before the choice is made.
                Text(L10n.System.spotlightNote)
                    .font(.dsNote)
                    .foregroundStyle(Color.dsSecondaryText)
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)

            Section(title: L10n.System.promiseTitle) {
                Text(L10n.System.promiseBody)
                    .accessibilityIdentifier("privacy.promise")
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)

            Section {
                Button(role: .destructive) { isErasing = true } label: {
                    Text(L10n.System.eraseEverything)
                        .foregroundStyle(Color.dsRecord)
                        .tappableTarget()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("privacy.erase")
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)
        }
        .screenList()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.System.privacyTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isErasing) { EraseSheet(controller: controller) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.privacy")
    }
}

/// Nothing comes back after this, so it asks for more than a tap.
private struct EraseSheet: View {
    let controller: SystemController
    @State private var typed = ""
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    private var isConfirmed: Bool {
        typed.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(L10n.System.eraseWord) == .orderedSame
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.System.eraseWarning)
                    TextField(L10n.System.eraseInstruction(L10n.System.eraseWord), text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("erase.confirm")
                }
                Section {
                    Button(L10n.System.eraseEverything, role: .destructive) {
                        Task {
                            if await controller.eraseEverything() {
                                dismiss()
                                router.select(.home)
                            } else {
                                failed = true
                            }
                        }
                    }
                    .disabled(!isConfirmed || controller.isErasing)
                    .accessibilityIdentifier("erase.run")
                    if controller.isErasing {
                        ProgressView()
                    }
                    if failed {
                        Text(L10n.System.errorRecording)
                            .foregroundStyle(Color.dsRecord)
                    }
                }
            }
            .navigationTitle(L10n.System.eraseEverything)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
            }
        }
    }
}
