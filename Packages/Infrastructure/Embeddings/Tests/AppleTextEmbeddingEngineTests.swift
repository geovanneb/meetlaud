import Domain
@testable import Embeddings
import Foundation
import Testing

struct AppleTextEmbeddingEngineTests {
    private let engine = AppleTextEmbeddingEngine()

    private func dot(_ lhs: [Float], _ rhs: [Float]) -> Float {
        zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
    }

    @Test(arguments: [
        ("We agreed to move the launch to March", "en"),
        ("Combinamos adiar o lançamento para março porque não está pronto", "pt"),
        ("Acordamos retrasar el lanzamiento porque el proveedor no está listo", "es"),
        ("リリースを3月に延期することにしました", "ja"),
    ])
    func `the language of a question is recognized`(text: String, language: String) async {
        #expect(await engine.detectLanguage(of: text) == language)
    }

    @Test func `languages in Latin script share a model, and Japanese does not`() async {
        guard let english = await engine.modelID(language: "en") else { return }
        #expect(await engine.modelID(language: "pt") == english)
        #expect(await engine.modelID(language: "es") == english)
        #expect(await engine.modelID(language: "ja") != english)
    }

    @Test func `vectors have length one, and close meanings sit closer`() async throws {
        guard await engine.modelID(language: "en") != nil else { return }
        let vectors = try await engine.embed([
            "The server costs went up after we enabled logging",
            "Our infrastructure spending increased because of logs",
            "My cat sleeps on the sofa in the afternoon",
        ], language: "en")
        #expect(abs(dot(vectors[0], vectors[0]) - 1) < 0.001)
        #expect(dot(vectors[0], vectors[1]) > dot(vectors[0], vectors[2]))
        await engine.unload()
    }

    @Test func `text longer than the model can read does not fail`() async throws {
        guard await engine.modelID(language: "en") != nil else { return }
        let long = String(repeating: "word ", count: 5000)
        let vectors = try await engine.embed([long, ""], language: "en")
        #expect(vectors.count == 2)
        await engine.unload()
    }
}
