import Foundation

public struct LanguageRequest: Sendable {
    public let system: String
    public let prompt: String
    public let maxTokens: Int
    public let temperature: Float

    public init(system: String, prompt: String, maxTokens: Int, temperature: Float = 0.3) {
        self.system = system
        self.prompt = prompt
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

/// Writes text. Every model in the app sits behind this.
/// What a language model's speed test measured. Writing speed has no bearing on how good the text is.
public struct LanguageSpeed: Hashable, Sendable {
    public let modelID: String
    public let tokensPerSecond: Double
    public let firstTokenSeconds: Double

    public init(modelID: String, tokensPerSecond: Double, firstTokenSeconds: Double) {
        self.modelID = modelID
        self.tokensPerSecond = tokensPerSecond
        self.firstTokenSeconds = firstTokenSeconds
    }

    /// About three quarters of a word per token in English, which is close enough for one rounded number.
    public var wordsPerMinute: Int {
        Int((tokensPerSecond * 45 / 10).rounded()) * 10
    }
}

public protocol LanguageModelEngine: ModelRunner {
    func generate(_ request: LanguageRequest) -> AsyncThrowingStream<String, any Error>
}

/// What a language model did on this device, for SP-1.
public struct LanguageProbeResult: Codable, Sendable {
    public let label: String
    public let promptCharacters: Int
    public let loadSeconds: Double
    public let firstChunkSeconds: Double
    public let chunksPerSecond: Double
    public let chunks: Int
    public let lowestAvailableMemoryMB: Int
    public let thermalStart: Int
    public let thermalEnd: Int
    public let output: String
    public let error: String?

    public init(
        label: String,
        promptCharacters: Int,
        loadSeconds: Double,
        firstChunkSeconds: Double,
        chunksPerSecond: Double,
        chunks: Int,
        lowestAvailableMemoryMB: Int,
        thermalStart: Int,
        thermalEnd: Int,
        output: String,
        error: String?,
    ) {
        self.label = label
        self.promptCharacters = promptCharacters
        self.loadSeconds = loadSeconds
        self.firstChunkSeconds = firstChunkSeconds
        self.chunksPerSecond = chunksPerSecond
        self.chunks = chunks
        self.lowestAvailableMemoryMB = lowestAvailableMemoryMB
        self.thermalStart = thermalStart
        self.thermalEnd = thermalEnd
        self.output = output
        self.error = error
    }
}
