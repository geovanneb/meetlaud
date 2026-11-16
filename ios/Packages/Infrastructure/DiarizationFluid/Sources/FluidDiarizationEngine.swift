import Domain
@preconcurrency import FluidAudio
import Foundation

/// Tells who spoke when, on the device, from files already downloaded.
public actor FluidDiarizationEngine: DiarizationEngine {
    /// Models are shareable, unlike the manager, which is made fresh for each run.
    private var models: OfflineDiarizerModels?

    public init() {
        // FluidAudio can download models by itself. Nothing in this app may reach the network outside
        // ModelDelivery, so a missing file must fail here instead.
        ModelHub.offlineMode = true
    }

    public func prepare(model _: ModelDescriptor, folder: URL?) async throws {
        guard models == nil else { return }
        guard let folder else { throw TranscriptionError.modelNotInstalled }
        try Self.writeRevisionMarker(in: folder)
        models = try await OfflineDiarizerModels.load(from: folder)
    }

    /// FluidAudio treats a folder with no marker as stale, and would refuse it. The catalog pins the same revision
    /// that this version of the package expects, so the files are the right ones.
    private static func writeRevisionMarker(in folder: URL) throws {
        let marker = folder
            .appending(path: Repo.diarizer.folderName)
            .appending(path: ".fluidaudio-revision")
        try Data(Repo.diarizer.revision.utf8).write(to: marker, options: .atomic)
    }

    public func diarize(file: URL, speakers: SpeakerCount) async throws -> [SpeakerTurn] {
        guard let models else { throw TranscriptionError.modelNotInstalled }
        let config = Self.config(for: speakers)
        // Read once. Finding the voices is the slow part, and grouping them again costs a fraction of a second.
        let (source, _) = try AudioSourceFactory().makeDiskBackedSource(
            from: file, targetSampleRate: config.segmentation.sampleRate,
        )
        defer { source.cleanup() }
        let manager = OfflineDiarizerManager(config: config)
        manager.initialize(models: models)
        let prepared = try await manager.prepare(audioSource: source)
        let found = try Self.turns(manager.cluster(prepared))
        guard speakers == .automatic else { return found }
        return try Self.moreDistinctVoices(than: found, in: prepared, models: models)
    }

    /// The automatic count can merge people whose voices are plainly apart (SP-3). Tries one more speaker at a time,
    /// and keeps the largest count whose voices all stay clearly different. Stops at the first count that is not.
    private static func moreDistinctVoices(
        than found: [SpeakerTurn],
        in prepared: PreparedDiarization,
        models: OfflineDiarizerModels,
    ) throws -> [SpeakerTurn] {
        var best = found
        var count = Set(found.map(\.speaker)).count
        while count < VoiceSeparation.mostSpeakers {
            let manager = OfflineDiarizerManager(config: config(for: .exactly(count + 1)))
            manager.initialize(models: models)
            let candidate = try turns(manager.cluster(prepared))
            guard Set(candidate.map(\.speaker)).count == count + 1,
                  VoiceSeparation.areDistinct(candidate) else { break }
            best = candidate
            count += 1
        }
        return best
    }

    private static func turns(_ result: DiarizationResult) -> [SpeakerTurn] {
        result.segments.map { segment in
            SpeakerTurn(
                speaker: segment.speakerId,
                start: Double(segment.startTimeSeconds),
                end: Double(segment.endTimeSeconds),
                embedding: segment.embedding,
            )
        }
    }

    /// The model's own settings, unless the person said how many people spoke. On a short recording from a phone
    /// on a table, the automatic count sits on a knife edge: the same audio, decoded two slightly different ways,
    /// came out as one voice or as three. A known count holds steady (SP-3).
    static func config(for speakers: SpeakerCount) -> OfflineDiarizerConfig {
        var config = OfflineDiarizerConfig()
        if case let .exactly(count) = speakers {
            config.clustering.numSpeakers = count
        }
        return config
    }

    public func unload() async {
        models = nil
    }
}
