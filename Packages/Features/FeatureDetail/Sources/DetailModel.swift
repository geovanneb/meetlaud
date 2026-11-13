import Domain
import FeatureShared
import Foundation
import Localization
import Observation
import UIKit

@MainActor
@Observable
public final class DetailModel {
    public private(set) var recording: Recording?
    public private(set) var markers: [Marker] = []
    public private(set) var pauses: [PauseSpan] = []
    public private(set) var time: TimeInterval = 0
    public private(set) var isPlaying = false
    public private(set) var failed = false
    public private(set) var rate: Float = 1
    public private(set) var segments: [TranscriptSegment] = []
    public private(set) var transcript: Transcript?
    public private(set) var activeSegmentID: UUID?
    public private(set) var speakers: [Speaker] = []
    public private(set) var hasAudio = true
    public internal(set) var summaries: [Summary] = []
    public var selectedSummaryID: UUID?

    @ObservationIgnored private var activeSegmentIndex: Int?

    @ObservationIgnored let id: RecordingID
    @ObservationIgnored let startTime: TimeInterval?
    @ObservationIgnored private let store: any RecordingStore
    @ObservationIgnored let files: any RecordingFiles
    @ObservationIgnored private let player: any AudioPlaying
    @ObservationIgnored private let library: LibraryService
    @ObservationIgnored private let transcripts: any TranscriptStore
    @ObservationIgnored let center: TranscriptionCenter
    @ObservationIgnored private let speakerStore: any SpeakerStore
    @ObservationIgnored private let speakerService: SpeakerService
    @ObservationIgnored let summaryCenter: SummaryCenter
    @ObservationIgnored let reminders: any RemindersProvider

    public init(
        id: RecordingID,
        startTime: TimeInterval?,
        store: any RecordingStore,
        files: any RecordingFiles,
        player: any AudioPlaying,
        library: LibraryService,
        transcripts: any TranscriptStore,
        center: TranscriptionCenter,
        speakerStore: any SpeakerStore,
        speakerService: SpeakerService,
        summaryCenter: SummaryCenter,
        reminders: any RemindersProvider,
    ) {
        self.summaryCenter = summaryCenter
        self.reminders = reminders
        self.library = library
        self.transcripts = transcripts
        self.center = center
        self.speakerStore = speakerStore
        self.speakerService = speakerService
        self.id = id
        self.startTime = startTime
        self.store = store
        self.files = files
        self.player = player
    }

    public var duration: TimeInterval {
        max(player.duration, recording?.duration ?? 0)
    }

    func load() async {
        do {
            recording = try await store.recording(id)
            markers = try await store.markers(for: id)
            pauses = try await store.pauses(for: id)
            guard let recording else {
                failed = true
                return
            }
            await refreshTranscript()
            await refreshSummaries()
            do {
                try player.load(files.audioFile(for: id), title: recording.title)
                if let startTime {
                    seek(to: startTime)
                }
            } catch {
                // Text is still worth reading with no audio, so only an empty recording counts as a failure.
                hasAudio = false
                failed = segments.isEmpty
            }
        } catch {
            failed = true
        }
    }

    /// Follows the player while the screen is open. `.task` cancels it when the screen goes away.
    func trackPlayback() async {
        while !Task.isCancelled {
            time = player.currentTime
            isPlaying = player.isPlaying
            updateActiveSegment()
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func refreshTranscript() async {
        transcript = try? await transcripts.transcript(for: id)
        segments = await (try? transcripts.segments(for: id)) ?? []
        activeSegmentIndex = nil
        updateActiveSegment()
        speakers = await (try? speakerStore.speakers(for: id)) ?? []
    }

    func speaker(of segment: TranscriptSegment) -> Speaker? {
        speakers.first { $0.id.uuidString == segment.speaker }
    }

    func name(of speaker: Speaker) -> String {
        speaker.name ?? L10n.People.numbered(speaker.number)
    }

    func savedPeople() async -> [Person] {
        await (try? speakerStore.people()) ?? []
    }

    func rename(_ speaker: Speaker, to name: String) async {
        try? await speakerService.rename(speaker, to: name)
        await refreshTranscript()
    }

    func assign(_ speaker: Speaker, to person: Person) async {
        try? await speakerService.assign(speaker, to: person)
        await refreshTranscript()
    }

    func merge(_ speaker: Speaker, into target: Speaker) async {
        try? await speakerService.merge(speaker, into: target)
        await refreshTranscript()
    }

    func confirm(_ speaker: Speaker) async {
        try? await speakerService.confirm(speaker)
        await refreshTranscript()
    }

    func setSpeaker(_ speaker: Speaker, for segment: TranscriptSegment) async {
        try? await speakerService.setSpeaker(speaker, forSegment: segment.id)
        await refreshTranscript()
    }

    enum SaveVoiceResult {
        case saved, tooLittleSpeech, unavailable
    }

    func saveVoice(of speaker: Speaker, name: String) async -> SaveVoiceResult {
        do {
            try await speakerService.saveVoicePrint(of: speaker, name: name)
            await refreshTranscript()
            return .saved
        } catch SpeakerError.tooLittleSpeech {
            return .tooLittleSpeech
        } catch {
            return .unavailable
        }
    }

    // MARK: - Playback

    private func updateActiveSegment() {
        // Near the same place almost always, and a transcript can hold thousands of phrases.
        if let index = activeSegmentIndex, segments.indices.contains(index) {
            let current = segments[index]
            if current.start <= time, time < current.end {
                return
            }
        }
        activeSegmentIndex = segments.lastIndex { $0.start <= time && time < $0.end + 0.5 }
        activeSegmentID = activeSegmentIndex.map { segments[$0].id }
    }

    var progress: JobProgress? {
        center.progress[id]
    }

    /// Voices separated again on a finished transcript. The text is there, so only the speakers show work.
    var isRedetectingSpeakers: Bool {
        progress?.phase == .separatingSpeakers && transcript?.isComplete == true
    }

    /// A transcription at work, with its steps. Nil while only voices are separated again.
    var transcriptionProgress: JobProgress? {
        isRedetectingSpeakers ? nil : progress
    }

    func transcribe(language: String?, whenCharging: Bool = false) async -> TranscribeOutcome {
        await center.transcribe(id, language: language, whenCharging: whenCharging)
    }

    func transcribePlan(language: String?) async -> TranscribePlan? {
        await center.plan(duration: recording?.duration ?? 0, language: language)
    }

    func versions() async -> [TranscriptVersion] {
        await (try? transcripts.versions(for: id)) ?? []
    }

    func restore(_ version: TranscriptVersion) async {
        await center.restore(version)
        await refreshTranscript()
    }

    func canSeparateSpeakers() async -> Bool {
        await center.canSeparateSpeakers()
    }

    func redetectSpeakers(_ count: SpeakerCount) async {
        await center.redetectSpeakers(id, count: count)
        await refreshTranscript()
    }

    func cancelTranscription() async {
        await center.cancel(id)
        await refreshTranscript()
    }

    func save(_ segment: TranscriptSegment) async {
        try? await transcripts.update(segment)
        await refreshTranscript()
    }

    func replaceAll(_ text: String, with replacement: String) async -> Int {
        let count = await (try? transcripts.replaceAll(in: id, of: text, with: replacement)) ?? 0
        await refreshTranscript()
        return count
    }

    func togglePlayback() {
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying = player.isPlaying
    }

    func seek(to target: TimeInterval) {
        player.seek(to: target)
        time = player.currentTime
        updateActiveSegment()
    }

    func play(from target: TimeInterval) {
        seek(to: target)
        if !player.isPlaying {
            togglePlayback()
        }
    }

    func setRate(_ value: Float) {
        rate = value
        player.rate = value
    }

    func close() {
        player.stop()
    }

    func rename(to title: String) async {
        try? await library.rename(id, to: title)
        recording = try? await store.recording(id)
    }

    func moveToTrash() async {
        try? await library.trash([id])
    }

    func image(for marker: Marker) -> UIImage? {
        guard
            let name = marker.attachment,
            let directory = try? files.attachmentsDirectory(for: id)
        else { return nil }
        return UIImage(contentsOfFile: directory.appending(path: name).path)
    }
}
