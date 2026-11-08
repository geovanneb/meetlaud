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

    public func diarize(file: URL) async throws -> [SpeakerTurn] {
        guard let models else { throw TranscriptionError.modelNotInstalled }
        let manager = OfflineDiarizerManager()
        manager.initialize(models: models)
        let result = try await manager.process(file)
        return result.segments.map { segment in
            SpeakerTurn(
                speaker: segment.speakerId,
                start: Double(segment.startTimeSeconds),
                end: Double(segment.endTimeSeconds),
                embedding: segment.embedding,
            )
        }
    }

    public func unload() async {
        models = nil
    }
}
