import Domain
import Foundation

/// Passes every request to the real engine, and with `SUMMARY_EVAL_LOG=<file>` writes each request and answer there.
final class LoggingEngine: LanguageModelEngine {
    private let inner: any LanguageModelEngine
    private let log: URL?

    init(_ inner: any LanguageModelEngine) {
        self.inner = inner
        log = ProcessInfo.processInfo.environment["SUMMARY_EVAL_LOG"].map { URL(filePath: $0) }
    }

    func prepare(model: ModelDescriptor, folder: URL?) async throws {
        try await inner.prepare(model: model, folder: folder)
    }

    func unload() async {
        await inner.unload()
    }

    func generate(_ request: LanguageRequest) -> AsyncThrowingStream<String, any Error> {
        guard let log else { return inner.generate(request) }
        let stream = inner.generate(request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                var text = ""
                do {
                    for try await chunk in stream {
                        text += chunk
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                let entry = "=== SYSTEM\n\(request.system)\n=== PROMPT\n\(request.prompt)\n=== ANSWER\n\(text)\n\n"
                if let handle = try? FileHandle(forWritingTo: log) {
                    handle.seekToEndOfFile()
                    handle.write(Data(entry.utf8))
                    try? handle.close()
                } else {
                    try? Data(entry.utf8).write(to: log)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
