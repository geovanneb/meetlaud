import Domain
import Foundation
import MLX
import MLXLLM
import MLXLMCommon
@preconcurrency import Tokenizers

/// Runs a language model on the GPU, from files already on the device.
///
/// iOS can refuse the GPU in the background, and Metal work submitted there can crash the app. So this engine says
/// that it needs the foreground, and callers must respect that.
public actor MLXLanguageEngine: LanguageModelEngine {
    /// MLX keeps freed buffers for reuse. This limit stops that cache from growing into the memory budget.
    private static let cacheLimit = 256 * 1024 * 1024

    private var container: ModelContainer?

    public init() {}

    public func prepare(model _: ModelDescriptor, folder: URL?) async throws {
        guard container == nil else { return }
        guard let folder else { throw TranscriptionError.modelNotInstalled }
        Memory.cacheLimit = Self.cacheLimit
        container = try await LLMModelFactory.shared.loadContainer(from: folder, using: LocalTokenizerLoader())
    }

    public nonisolated func generate(_ request: LanguageRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let container = await self.loaded else { throw TranscriptionError.modelNotInstalled }
                    let session = ChatSession(
                        container,
                        instructions: request.system,
                        generateParameters: GenerateParameters(
                            maxTokens: request.maxTokens,
                            temperature: request.temperature,
                        ),
                    )
                    for try await chunk in session.streamResponse(to: request.prompt) {
                        try Task.checkCancellation()
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private var loaded: ModelContainer? {
        container
    }

    public func unload() async {
        container = nil
        Memory.clearCache()
    }
}

/// Reads the tokenizer from the model's folder. There is no download path here.
private struct LocalTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        try await TokenizerBridge(upstream: AutoTokenizer.from(modelFolder: directory))
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer, @unchecked Sendable {
    let upstream: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? {
        upstream.bosToken
    }

    var eosToken: String? {
        upstream.eosToken
    }

    var unknownToken: String? {
        upstream.unknownToken
    }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?,
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages, tools: tools, additionalContext: additionalContext,
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
