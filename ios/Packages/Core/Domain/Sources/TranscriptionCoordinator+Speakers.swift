import Foundation

// MARK: - Speakers again

public extension TranscriptionCoordinator {
    /// Whether voices can be separated at all: a speaker model is installed.
    func canSeparateSpeakers() async -> Bool {
        await speakers?.isAvailable() ?? false
    }

    /// Separates voices again on a finished transcript, for example with the number of people the person knows
    /// spoke. The text stays as it is. Names come back as suggestions from saved voices, since the old speakers no
    /// longer line up with the new ones.
    func redetectSpeakers(_ id: RecordingID, count: SpeakerCount) async throws {
        guard let speakers, await speakers.isAvailable() else { return }
        // A transcription still running for this meeting will separate voices itself.
        guard try await store.job(for: id) == nil else { return }
        // Waits for any other heavy model, so that two are never loaded at once.
        await arbiter.acquire()
        includesSpeakers = true
        report(id, .separatingSpeakers, 1)
        do {
            try await speakers.run(id: id, file: files.audioFile(for: id), speakers: count)
        } catch {
            progress[id] = nil
            await arbiter.release()
            throw error
        }
        progress[id] = nil
        await arbiter.release()
    }
}
