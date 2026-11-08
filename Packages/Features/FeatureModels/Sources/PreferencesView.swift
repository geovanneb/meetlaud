import AppRouting
import DesignSystem
import Domain
import FeatureShared
import Localization
import SwiftUI

public struct PreferencesView: View {
    private let controller: ModelsController
    @AppStorage(AutoTranscribe.storageKey) private var auto: AutoTranscribe = .ask
    @AppStorage(SummaryPreferences.autoKey) private var autoSummary = false
    @AppStorage(SummaryPreferences.profileKey) private var profile = ""
    @AppStorage(AskPreferences.promptBarKey) private var promptBar = AskPreferences.PromptBar.focus.rawValue
    @AppStorage(WidgetPreferences.showContentKey) private var showsContentInWidgets = false
    @Environment(AppRouter.self) private var router
    @State private var isChoosingAuto = false
    @State private var isChoosingPromptBar = false
    private static let supported = ["en", "ja", "pt", "es"]

    public init(controller: ModelsController) {
        self.controller = controller
    }

    public var body: some View {
        List {
            Section(title: L10n.Transcript.title) {
                Button { isChoosingAuto = true } label: {
                    SettingsRowLabel(L10n.Transcript.autoLabel, value: auto.title)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("preferences.auto")
                Button { router.push(.vocabulary) } label: {
                    SettingsRowLabel(L10n.Vocabulary.title)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("preferences.vocabulary")
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)

            Section {
                Toggle(L10n.Summary.auto, isOn: $autoSummary)
                    .accessibilityIdentifier("preferences.autoSummary")
            } header: {
                SectionHeader(L10n.Summary.title)
            } footer: {
                Text(L10n.Summary.autoNote)
                    .foregroundStyle(Color.dsSecondaryText)
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)

            Section {
                TextField(L10n.Summary.profileHint, text: $profile, axis: .vertical)
                    .lineLimit(3 ... 8)
                    .onChange(of: profile) { _, text in
                        if text.count > SummaryPreferences.profileLimit {
                            profile = String(text.prefix(SummaryPreferences.profileLimit))
                        }
                    }
                    .accessibilityIdentifier("preferences.profile")
            } header: {
                SectionHeader(L10n.Summary.profile)
            } footer: {
                Text(L10n.Summary.profileNote(profile.count, SummaryPreferences.profileLimit))
                    .foregroundStyle(Color.dsSecondaryText)
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)

            Section(title: L10n.Nav.ask) {
                Button { isChoosingPromptBar = true } label: {
                    SettingsRowLabel(
                        L10n.Ask.promptBar,
                        value: promptBar == AskPreferences.PromptBar.focus.rawValue
                            ? L10n.Ask.promptFocus : L10n.Ask.promptNew,
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("preferences.promptBar")
                Button { router.push(.memory) } label: {
                    SettingsRowLabel(L10n.Ask.memory)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("preferences.memory")
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)

            Section {
                Toggle(L10n.Widgets.showContent, isOn: $showsContentInWidgets)
                    .accessibilityIdentifier("preferences.widgetContent")
            } header: {
                SectionHeader(L10n.Widgets.title)
            } footer: {
                Text(L10n.Widgets.showContentNote)
                    .foregroundStyle(Color.dsSecondaryText)
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)

            Section(title: L10n.Models.spokenLanguages) {
                ForEach(Self.supported, id: \.self) { code in
                    Button {
                        toggle(code)
                    } label: {
                        HStack {
                            Text(languageName(code))
                            Spacer()
                            if controller.languages.contains(code) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.dsAction)
                                    .accessibilityHidden(true)
                            }
                        }
                        .tappableTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(controller.languages.contains(code) ? .isSelected : [])
                }
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)
        }
        .screenList()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.Settings.preferences)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $isChoosingAuto) {
            ChoiceSheet(
                title: L10n.Transcript.autoLabel,
                closeLabel: L10n.Common.close,
                choices: AutoTranscribe.allCases.map { Choice($0, title: $0.title) },
                selection: $auto,
            )
        }
        .sheet(isPresented: $isChoosingPromptBar) {
            ChoiceSheet(
                title: L10n.Ask.promptBar,
                closeLabel: L10n.Common.close,
                choices: [
                    Choice(AskPreferences.PromptBar.focus.rawValue, title: L10n.Ask.promptFocus),
                    Choice(AskPreferences.PromptBar.newChat.rawValue, title: L10n.Ask.promptNew),
                ],
                selection: $promptBar,
            )
        }
        .accessibilityIdentifier("screen.preferences")
    }

    private func toggle(_ code: String) {
        var languages = controller.languages
        if languages.contains(code) {
            guard languages.count > 1 else { return }
            languages.removeAll { $0 == code }
        } else {
            languages.append(code)
        }
        controller.setLanguages(languages)
    }
}
