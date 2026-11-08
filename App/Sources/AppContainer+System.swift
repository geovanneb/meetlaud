import Domain
import FeatureShared
import Foundation
import Localization
import SwiftUI
import SystemBridges
import UIKit
import WidgetKit

extension AppContainer {
    var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(version) (\(build))"
    }

    var licensesText: String {
        Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    /// Follows the library while the preference is on. Turning it off, or erasing everything, clears the index.
    func keepSpotlight(enabled: Bool) async {
        let index = SpotlightIndex()
        guard enabled else {
            await index.removeAll()
            return
        }
        for await recordings in store.observeRecordings() {
            await index.index(recordings)
        }
    }

    /// Everything that reaches the recorder from outside the app's screens.
    func handle(_ command: RecordingCommand) {
        switch command {
        case .togglePause: recorder.togglePause()
        case .stop: recorder.stop()
        case .mark: recorder.flag()
        case .start: recorder.record()
        case .toggle:
            if recorder.snapshot.status.isActive {
                recorder.stop()
            } else {
                recorder.record()
            }
        case .openLast:
            Task {
                let all = await (try? store.recordings(status: .ready)) ?? []
                let last = all.filter { $0.deletedAt == nil }.max { $0.createdAt < $1.createdAt }
                if let last {
                    router.open(.recording(last.id, at: nil))
                }
            }
        }
    }

    func sceneChanged(_ phase: ScenePhase) {
        lockWindow.start()
        switch phase {
        case .active: lock.becameActive()
        case .inactive: lock.becameInactive()
        case .background: lock.enteredBackground()
        @unknown default: break
        }
        lockWindow.refresh()
    }

    /// Only when the app is out of sight, and with no meeting content: this shows on the Lock Screen.
    nonisolated static func notifyTranscriptReady(notifier: any LocalNotifier, gate: GenerationGate) async {
        guard !gate.isForeground, UserDefaults.standard.bool(forKey: NotificationPreferences.transcriptReadyKey) else {
            return
        }
        await notifier.notify(id: UUID().uuidString, title: L10n.System.transcriptReadyTitle, body: "")
    }

    /// Runs on the way out of the app, which is when the Home Screen and its widgets become visible.
    func refreshWidgets() async {
        guard UserDefaults.standard.bool(forKey: WidgetPreferences.showContentKey) else {
            WidgetSnapshot.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let all = await (try? store.recordings(status: .ready)) ?? []
        let recent = all.filter { $0.deletedAt == nil }.sorted { $0.createdAt > $1.createdAt }.prefix(3)
        WidgetSnapshot(
            nextEvent: home.events.first.map { WidgetSnapshot.Event(title: $0.title, start: $0.start) },
            recent: recent.map { WidgetSnapshot.Meeting(id: $0.id.rawValue, title: $0.title, date: $0.createdAt) },
        )
        .save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func scheduleReminders() async {
        let wanted = UserDefaults.standard.bool(forKey: NotificationPreferences.eventRemindersKey)
        await services.notifier.scheduleReminders(
            for: wanted ? Array(home.events.prefix(10)) : [],
            title: L10n.System.eventReminderTitle,
        )
    }

    /// Stops everything that touches the library. Refuses during a recording, which comes first.
    func pauseAllWork() async -> Bool {
        guard !recorder.snapshot.status.isActive else { return false }
        await askQueue.stopAndRelease()
        await knowledgeIndexer.suspend()
        await summaryQueue.suspend()
        player.stop()
        return true
    }

    func resumeAllWork() async {
        await summaryQueue.resume()
        await knowledgeIndexer.run()
        try? await transcriptions.resumeInterrupted(countKills: false)
    }

    func eraseEverything() async throws {
        for job in try await services.transcripts.jobs() {
            try await transcriptions.cancel(job.recordingID)
        }
        try await services.snapshots.eraseEverything()
        try services.storage.removeEverything()
        await modelManager.removeAllModels()
        await services.notifier.scheduleReminders(for: [], title: "")
        WidgetSnapshot.clear()
        WidgetCenter.shared.reloadAllTimelines()
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        if lock.state.isEnabled {
            lock.forgetLock()
        }
    }
}
