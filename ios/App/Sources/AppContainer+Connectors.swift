import Connectors
import Domain
import FeatureShared
import Foundation

/// Adapts the library to what connectors can see. This is the only place that knows both sides, and it passes along
/// nothing beyond what a connector asked for.
struct LibraryConnectorSource: ConnectorMeetingSource {
    let store: any RecordingStore
    let transcripts: any TranscriptStore
    let speakers: any SpeakerStore
    let files: any RecordingFiles
    let usage: any ModelUsageStore

    func finishedMeetings() async -> [ConnectorMeeting] {
        let ready = await (try? store.recordings(status: .ready)) ?? []
        return ready.filter { $0.deletedAt == nil }.map {
            ConnectorMeeting(id: $0.id.rawValue, createdAt: $0.createdAt)
        }
    }

    func package(for id: UUID, including content: Set<ConnectorContent>) async -> ConnectorPackage? {
        let recordingID = RecordingID(rawValue: id)
        guard let recording = try? await store.recording(recordingID) else { return nil }
        var package = ConnectorPackage(id: id, title: recording.title, date: recording.createdAt)
        if content.contains(.audio) {
            package.audioFile = files.audioFile(for: recordingID)
        }
        if content.contains(.transcript) {
            // A transcript on its way is worth the wait. It goes with the meeting, not after it.
            guard await (try? transcripts.job(for: recordingID)) == nil else { return nil }
            package.transcript = await transcript(of: recording)
        }
        if content.contains(.photos) {
            package.photos = await photos(of: recordingID)
        }
        return package
    }

    private func transcript(of recording: Recording) async -> String? {
        let segments = await (try? transcripts.segments(for: recording.id)) ?? []
        guard !segments.isEmpty else { return nil }
        let people = await (try? speakers.speakers(for: recording.id)) ?? []
        return TranscriptExporter.text(title: recording.title, segments: segments, speakers: people, format: .vtt)
    }

    private func photos(of id: RecordingID) async -> [URL] {
        guard let folder = try? files.attachmentsDirectory(for: id) else { return [] }
        let markers = await (try? store.markers(for: id)) ?? []
        return markers.compactMap { marker in marker.attachment.map { folder.appending(path: $0) } }
    }

    /// The same log as model downloads, so that Network activity stays the whole truth. Titles never go in it.
    func logDelivery(of package: ConnectorPackage, to connector: ConnectorManifest) async {
        let size = package.audioFile.flatMap {
            try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int64
        }
        try? await usage.logNetwork(NetworkLogEntry(
            host: connector.name, modelID: connector.id, bytes: size ?? 0, date: Date(),
        ))
    }
}

extension AppContainer {
    /// While the app is active, each new meeting or sighting of a linked computer starts a delivery.
    func keepConnectorsInSync() async {
        let sync = connectorSync
        let store = services.store
        let connectors = connectors.connectors
        await sync.run()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in store.observeRecordings() {
                    await sync.run()
                }
            }
            for connector in connectors {
                group.addTask {
                    for await _ in connector.peerChanges() {
                        await sync.run()
                    }
                }
            }
        }
    }
}
