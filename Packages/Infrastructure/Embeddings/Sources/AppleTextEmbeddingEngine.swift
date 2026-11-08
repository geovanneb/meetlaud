import Accelerate
import Domain
import Foundation
import NaturalLanguage

/// Embeds text with the models built into iOS, so that search needs no download of ours and no extra license.
///
/// Latin languages share one model, and Japanese has its own. A question can only reach text from the same model, which
/// is why `modelID` matters here: Portuguese finds English by meaning, and Japanese does not. See SP-5.
public actor AppleTextEmbeddingEngine: TextEmbeddingEngine {
    private static let supported: [NLLanguage] = [.english, .japanese, .portuguese, .spanish]
    /// The model reads about 256 tokens and ignores the rest. Chunks stay under this, and pasted text might not.
    private static let characterLimit = 1200

    private var loaded: [String: NLContextualEmbedding] = [:]

    public init() {}

    private static func nativeLanguage(_ code: String?) -> NLLanguage {
        guard let code else { return .english }
        return supported.first { $0.rawValue == code } ?? NLLanguage(rawValue: code)
    }

    public func prepare(model _: ModelDescriptor, folder _: URL?) async throws {}

    public func unload() async {
        for embedding in loaded.values {
            embedding.unload()
        }
        loaded = [:]
    }

    public func modelID(language: String?) async -> String? {
        guard
            let embedding = NLContextualEmbedding(language: Self.nativeLanguage(language)),
            embedding.hasAvailableAssets
        else { return nil }
        return embedding.modelIdentifier
    }

    public func detectLanguage(of text: String) async -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = Self.supported
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    public func embed(_ texts: [String], language: String?) async throws -> [[Float]] {
        let native = Self.nativeLanguage(language)
        let embedding = try model(for: native)
        return try texts.map { text in
            try Self.vector(for: String(text.prefix(Self.characterLimit)), native, embedding)
        }
    }

    private func model(for language: NLLanguage) throws -> NLContextualEmbedding {
        if let existing = loaded[language.rawValue] {
            return existing
        }
        guard let embedding = NLContextualEmbedding(language: language), embedding.hasAvailableAssets else {
            throw TranscriptionError.modelNotInstalled
        }
        try embedding.load()
        loaded[language.rawValue] = embedding
        return embedding
    }

    /// One vector per token comes back. Their average stands for the text, scaled to length 1.
    private static func vector(
        for text: String,
        _ language: NLLanguage,
        _ embedding: NLContextualEmbedding,
    ) throws -> [Float] {
        var sum = [Double](repeating: 0, count: embedding.dimension)
        guard !text.isEmpty else { return sum.map(Float.init) }
        let result = try embedding.embeddingResult(for: text, language: language)
        result.enumerateTokenVectors(in: text.startIndex ..< text.endIndex) { vector, _ in
            vDSP_vaddD(sum, 1, vector, 1, &sum, 1, vDSP_Length(sum.count))
            return true
        }
        let length = sqrt(vDSP_svesqD(sum))
        guard length > 0 else { return sum.map(Float.init) }
        return sum.map { Float($0 / length) }
    }
}

/// Whether iOS has the embedding models, and asks for them when it does not. iOS does the fetching.
public struct AppleEmbeddingAssets: SystemSpeechAssets {
    public init() {}

    private static func embedding(_ language: String) -> NLContextualEmbedding? {
        NLContextualEmbedding(language: NLLanguage(rawValue: language))
    }

    public func isInstalled(language: String) async -> Bool {
        Self.embedding(language)?.hasAvailableAssets == true
    }

    public func install(language: String) async throws {
        guard let embedding = Self.embedding(language) else { throw TranscriptionError.languageNotSupported }
        guard !embedding.hasAvailableAssets else { return }
        let result = try await embedding.requestAssets()
        guard result == .available else { throw TranscriptionError.modelNotInstalled }
    }
}

private func vDSP_svesqD(_ values: [Double]) -> Double {
    vDSP.sumOfSquares(values)
}
