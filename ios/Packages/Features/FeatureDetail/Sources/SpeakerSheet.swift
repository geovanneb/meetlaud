import DesignSystem
import Domain
import Localization
import SwiftUI

/// Everything about one speaker in this recording, from a tap on their name.
struct SpeakerSheet: View {
    let speaker: Speaker
    let model: DetailModel
    @State private var name = ""
    @State private var people: [Person] = []
    @State private var remembersVoice = false
    @State private var isConfirmingVoice = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var others: [Speaker] {
        model.speakers.filter { $0.id != speaker.id }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                if speaker.isSuggested {
                    Section {
                        Text(L10n.People.suggestion(speaker.name ?? ""))
                        Button(L10n.People.confirm) { act { await model.confirm(speaker) } }
                            .accessibilityIdentifier("speaker.confirm")
                    }
                }
                Section(title: L10n.People.nameSection) {
                    TextField(L10n.Library.namePlaceholder, text: $name)
                        .accessibilityIdentifier("speaker.name")
                }
                if !people.isEmpty {
                    Section(title: L10n.People.pickSaved) {
                        ForEach(people) { person in
                            Button { act { await model.assign(speaker, to: person) } } label: {
                                Label(person.name, systemImage: "person.crop.circle")
                                    .foregroundStyle(Color.dsPrimaryText)
                            }
                        }
                    }
                }
                Section {
                    Toggle(
                        trimmedName.isEmpty ? L10n.People.saveVoice : L10n.People.rememberVoice(trimmedName),
                        isOn: $remembersVoice,
                    )
                    .disabled(trimmedName.isEmpty)
                    .accessibilityIdentifier("speaker.saveVoice")
                    if let error {
                        Text(error)
                            .foregroundStyle(Color.dsRecord)
                    }
                } footer: {
                    Text(L10n.People.saveVoiceNote)
                        .foregroundStyle(Color.dsSecondaryText)
                }
                if !others.isEmpty {
                    Section(title: L10n.People.mergeSection) {
                        ForEach(others) { other in
                            Button(model.name(of: other)) { act { await model.merge(speaker, into: other) } }
                        }
                    }
                }
            }
            .navigationTitle(model.name(of: speaker))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                // One way to finish: the name and the voice are saved together, for this speaker only.
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save, action: save)
                        .disabled(trimmedName.isEmpty)
                        .accessibilityIdentifier("speaker.save")
                }
            }
            .alert(L10n.People.consentTitle, isPresented: $isConfirmingVoice) {
                Button(L10n.People.consentAccept) { saveVoice() }
                    .accessibilityIdentifier("speaker.consent")
                Button(L10n.Common.cancel, role: .cancel) {}
            } message: {
                Text(L10n.People.consentMessage(trimmedName))
            }
        }
        .task {
            name = speaker.name ?? ""
            people = await model.savedPeople()
        }
    }

    private func save() {
        if remembersVoice {
            isConfirmingVoice = true
        } else {
            act { await model.rename(speaker, to: name) }
        }
    }

    private func act(_ work: @escaping @MainActor () async -> Void) {
        Task {
            await work()
            dismiss()
        }
    }

    private func saveVoice() {
        Task {
            switch await model.saveVoice(of: speaker, name: name) {
            case .saved: dismiss()
            case .tooLittleSpeech: error = L10n.People.tooLittleSpeech
            case .unavailable: error = L10n.People.saveFailed
            }
        }
    }
}
