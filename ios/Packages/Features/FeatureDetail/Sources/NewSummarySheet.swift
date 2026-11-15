import DesignSystem
import Domain
import Localization
import SwiftUI

/// Picks what a new summary looks like.
struct NewSummarySheet: View {
    let templates: [SummaryTemplate]
    @State var selected: SummaryTemplate
    let onGenerate: (SummaryTemplate, String?) -> Void
    @State private var language: String?
    @Environment(\.dismiss) private var dismiss
    private static let languages = ["en", "ja", "pt", "es"]

    var body: some View {
        NavigationStack {
            List {
                Picker(L10n.Summary.language, selection: $language) {
                    Text(L10n.Summary.languageAuto).tag(String?.none)
                    ForEach(Self.languages, id: \.self) { code in
                        Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(String?.some(code))
                    }
                }
                Section(title: L10n.Summary.template) {
                    ForEach(templates) { template in
                        Button {
                            selected = template
                        } label: {
                            HStack {
                                Text(L10n.Summary.templateName(template.name))
                                Spacer()
                                if template.id == selected.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.dsAction)
                                        .accessibilityHidden(true)
                                }
                            }
                            .tappableTarget()
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(template.id == selected.id ? .isSelected : [])
                    }
                }
            }
            .navigationTitle(L10n.Summary.add)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Summary.generateAction) {
                        onGenerate(selected, language)
                        dismiss()
                    }
                    .accessibilityIdentifier("summary.sheet.generate")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
