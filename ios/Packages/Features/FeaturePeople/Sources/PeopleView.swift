import AppRouting
import DesignSystem
import Domain
import FeatureShared
import Foundation
import Localization
import Observation
import SwiftUI

@MainActor
@Observable
public final class PeopleModel {
    public private(set) var people: [Person] = []
    @ObservationIgnored private let store: any SpeakerStore
    @ObservationIgnored private let service: SpeakerService
    @ObservationIgnored private let recordings: any RecordingStore

    public init(store: any SpeakerStore, service: SpeakerService, recordings: any RecordingStore) {
        self.store = store
        self.service = service
        self.recordings = recordings
    }

    func meetings(with person: Person) async -> [Recording] {
        let ids = await (try? service.recordings(with: person)) ?? []
        var found: [Recording] = []
        for id in ids {
            if let recording = try? await recordings.recording(id), recording.deletedAt == nil {
                found.append(recording)
            }
        }
        return found.sorted { $0.createdAt > $1.createdAt }
    }

    func merge(_ source: Person, into target: Person) async {
        try? await service.merge(source, into: target)
        await refresh()
    }

    func refresh() async {
        people = await (try? store.people()) ?? []
    }

    func rename(_ person: Person, to name: String) async {
        try? await service.rename(person, to: name)
        await refresh()
    }

    func delete(_ person: Person) async {
        try? await service.delete(person)
        await refresh()
    }
}

/// Saved voices. These are biometric data, so deleting one must be easy and final.
public struct PeopleView: View {
    private let model: PeopleModel
    @State private var renaming: Person?
    @State private var name = ""

    public init(model: PeopleModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.people.isEmpty {
                EmptyState(
                    title: L10n.People.emptyTitle,
                    message: L10n.People.emptyMessage,
                    symbol: "person.2",
                )
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(L10n.People.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refresh() }
        .modifier(NamePrompt(
            title: L10n.Library.rename,
            isPresented: Binding(
                get: { renaming != nil },
                set: {
                    if !$0 {
                        renaming = nil
                    }
                },
            ),
            name: $name,
        ) {
            if let renaming {
                let newName = name
                Task { await model.rename(renaming, to: newName) }
            }
        })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.people")
    }

    private var list: some View {
        List {
            Section {
                ForEach(model.people) { person in
                    NavigationLink {
                        PersonView(person: person, model: model)
                    } label: {
                        Text(person.name)
                    }
                    .listRowBackground(Color.clear)
                    .swipeActions {
                        Button(L10n.Library.delete, systemImage: "trash", role: .destructive) {
                            Task { await model.delete(person) }
                        }
                        Button(L10n.Library.rename, systemImage: "pencil") {
                            name = person.name
                            renaming = person
                        }
                    }
                }
            } footer: {
                Text(L10n.People.footer)
                    .foregroundStyle(Color.dsSecondaryText)
            }
        }
        .screenList()
    }
}

/// One saved person: where they spoke, and how to fix a duplicate.
struct PersonView: View {
    let person: Person
    let model: PeopleModel
    @State private var meetings: [Recording] = []
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    private var others: [Person] {
        model.people.filter { $0.id != person.id }
    }

    var body: some View {
        List {
            Section(title: L10n.People.meetings) {
                if meetings.isEmpty {
                    Text(L10n.People.noMeetings)
                        .font(.dsMeta)
                        .foregroundStyle(Color.dsSecondaryText)
                }
                ForEach(meetings) { recording in
                    Button {
                        router.push(.recording(recording.id, at: nil))
                    } label: {
                        RecordingRow(recording: recording)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden, edges: .top)
        }
        .screenList()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !others.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu(L10n.People.mergeInto, systemImage: "ellipsis") {
                        Section(L10n.People.mergeInto) {
                            ForEach(others) { other in
                                Button(other.name) {
                                    Task {
                                        await model.merge(person, into: other)
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("person.merge")
                }
            }
        }
        .task { meetings = await model.meetings(with: person) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.person")
    }
}
