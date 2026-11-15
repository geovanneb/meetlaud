import Foundation

/// What one model made of the same audio.
public struct ModelTrial: Identifiable, Hashable, Sendable {
    public let modelID: String
    public let text: String
    public let seconds: TimeInterval

    public var id: String {
        modelID
    }

    public init(modelID: String, text: String, seconds: TimeInterval) {
        self.modelID = modelID
        self.text = text
        self.seconds = seconds
    }
}

/// Speed tests for models that write and models that search.
public extension ModelManager {
    /// The same audio through each model, one at a time, so that a person can judge what no benchmark measures.
    func tryModels(_ ids: [String], on clip: AudioWindow) async throws -> [ModelTrial] {
        // Optional work gives way to real work, as a speed test does.
        guard await arbiter.tryAcquire() else { throw ModelArbiterError.busy }
        do {
            var trials: [ModelTrial] = []
            for id in ids {
                try Task.checkCancellation()
                try await trials.append(trial(of: id, on: clip))
            }
            await arbiter.release()
            return trials
        } catch {
            await arbiter.release()
            throw error
        }
    }

    private func trial(of id: String, on clip: AudioWindow) async throws -> ModelTrial {
        guard let model = catalog.models.first(where: { $0.id == id }),
              let runner = engines(model.runtime) as? any TranscriptionEngine
        else { throw TranscriptionError.modelNotInstalled }
        do {
            try await runner.prepare(model: model, folder: installer.folder(for: id))
            let started = now()
            let result = try await runner.transcribe(clip, language: nil)
            let seconds = now().timeIntervalSince(started)
            await runner.unload()
            return ModelTrial(modelID: id, text: result.segments.map(\.text).joined(separator: " "), seconds: seconds)
        } catch {
            await runner.unload()
            throw error
        }
    }

    /// Times a fixed batch of text, about what one meeting turns into.
    func runSearchTest(_ modelID: String) async throws -> SearchSpeed {
        guard let model = catalog.models.first(where: { $0.id == modelID }),
              let runner = engines(model.runtime) as? any TextEmbeddingEngine
        else { throw TranscriptionError.modelNotInstalled }
        guard await arbiter.tryAcquire() else { throw ModelArbiterError.busy }
        defer { Task { await arbiter.release() } }
        let batch = Array(repeating: SearchSpeed.sample, count: 48)
        do {
            let started = now()
            _ = try await runner.embed(batch, language: "en")
            let seconds = now().timeIntervalSince(started)
            await runner.unload()
            return SearchSpeed(modelID: modelID, passagesPerSecond: Double(batch.count) / max(seconds, 0.001))
        } catch {
            await runner.unload()
            throw error
        }
    }

    /// Times a short answer. Foreground only, like every use of a language model.
    func runLanguageTest(_ modelID: String) async throws -> LanguageSpeed {
        guard let model = catalog.models.first(where: { $0.id == modelID }),
              let runner = engines(model.runtime) as? any LanguageModelEngine
        else { throw TranscriptionError.modelNotInstalled }
        guard await arbiter.tryAcquire() else { throw ModelArbiterError.busy }
        defer { Task { await arbiter.release() } }
        do {
            try await runner.prepare(model: model, folder: installer.folder(for: modelID))
            let request = LanguageRequest(
                system: "You write clear notes.",
                prompt: "Explain in a few sentences why meetings should end with clear next steps.",
                maxTokens: 120,
            )
            let started = now()
            var first: Date?
            var chunks = 0
            for try await _ in runner.generate(request) {
                first = first ?? now()
                chunks += 1
            }
            try Task.checkCancellation()
            let writing = now().timeIntervalSince(first ?? started)
            await runner.unload()
            return LanguageSpeed(
                modelID: modelID,
                tokensPerSecond: Double(chunks) / max(writing, 0.001),
                firstTokenSeconds: (first ?? started).timeIntervalSince(started),
            )
        } catch {
            await runner.unload()
            throw error
        }
    }
}
