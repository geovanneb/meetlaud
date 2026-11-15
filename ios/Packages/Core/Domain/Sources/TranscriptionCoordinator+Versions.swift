import Foundation

// MARK: - Versions

public extension TranscriptionCoordinator {
    /// Brings an earlier transcript back. The current one becomes a version, so that this can be undone.
    func restore(_ version: TranscriptVersion) async throws {
        let id = version.recordingID
        guard try await store.job(for: id) == nil else { return }
        try await keepCurrentTranscript(of: id)
        try await store.deleteVersion(version.id)
        try await store.deleteTranscript(for: id)
        let job = TranscriptionJob(recordingID: id, modelID: version.modelID, language: version.language)
        try await store.save(Transcript(
            recordingID: id, modelID: version.modelID, language: version.language, isComplete: true,
        ))
        try await store.append(version.segments, job: job)
        try await store.deleteJob(for: id)
    }
}

extension TranscriptionCoordinator {
    func keepCurrentTranscript(of id: RecordingID) async throws {
        let segments = try await store.segments(for: id)
        guard !segments.isEmpty, let transcript = try await store.transcript(for: id) else { return }
        try await store.save(TranscriptVersion(
            recordingID: id,
            modelID: transcript.modelID,
            language: transcript.language,
            savedAt: now(),
            // Speakers belong to the transcript that replaces this one.
            segments: segments.map {
                TranscriptSegment(recordingID: id, start: $0.start, end: $0.end, text: $0.text)
            },
        ))
    }
}
