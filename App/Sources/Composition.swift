import AppRouting
import Domain
import FeatureAsk
import FeatureDetail
import FeatureHome
import FeatureLibrary
import FeatureModels
import FeaturePeople
import FeatureRecording
import FeatureSettings
import FeatureTools
import SwiftUI

/// The only place that knows every feature.
@MainActor
struct Composition {
    let container: AppContainer

    @ViewBuilder
    func screen(for destination: Destination) -> some View {
        switch destination {
        case .home:
            HomeView(
                model: container.home,
                center: container.transcription,
                onRecord: { container.recorder.record() },
                onRecordEvent: record,
                onImport: { container.library.presentFilePicker() },
            )
        case .library: LibraryView(library: container.library, center: container.transcription)
        case .ask: AskView(controller: container.ask)
        case .tools: ToolsView(
                center: container.summaries,
                skills: container.skills,
                connectors: container.connectors,
                recordings: container.transcribedRecordings,
            )
        case .settings: SettingsView()
        case .help: HelpView()
        }
    }

    /// One case per screen, by nature.
    @ViewBuilder
    func screen(for route: AppRoute) -> some View { // swiftlint:disable:this cyclomatic_complexity
        switch route {
        case let .recording(id, time):
            DetailView(model: container.detailModel(id: id, startTime: time))
        case .modelSettings: AIModelsView(controller: container.models)
        case .preferences: PreferencesView(controller: container.models)
        case .networkActivity: NetworkActivityView(controller: container.models)
        case .people: PeopleView(model: container.people)
        case .search: SearchView(library: container.library)
        case .trash: TrashView(library: container.library)
        case .calendar: CalendarScreen(model: container.home, onRecordEvent: record)
        case .ask(recording: nil), .record: EmptyView()
        case .licenses: LicensesView(text: container.licensesText)
        case .storage: StorageBackupView(controller: container.system)
        case .notifications: NotificationsView(controller: container.system)
        case .calendars: CalendarsView(model: container.calendars)
        case .vocabulary: VocabularyView(folders: container.library.folders)
        case .privacy: PrivacySecurityView(controller: container.system, lock: container.lock)
        case .about: AboutView(version: container.versionText)
        case .helpCenter: HelpView()
        case let .ask(.some(id)): ScopedChatView(controller: container.ask, scope: .recording(id))
        case let .askFolder(id): ScopedChatView(controller: container.ask, scope: .folder(id))
        case .memory: MemoryView(controller: container.ask)
        case let .askSkill(id):
            ScopedChatView(controller: container.ask, scope: .library, skill: container.skills.skill(id: id))
        }
    }

    private func record(_ event: CalendarEvent) {
        // A recording with no name gets the usual dated one, which beats an empty title.
        container.recorder.record(title: event.hasTitle ? event.title : nil, attendees: event.attendees)
    }
}
