import Foundation

public enum ModelArbiterError: Error, Equatable {
    /// Something else is using a model right now.
    case busy
}

/// Gives one piece of work at a time the right to load and run a heavy model.
///
/// Engines are shared, and unloading one in the middle of another's work crashes inside Core ML. Memory is the other
/// reason: two models at once is how iOS ends up killing the app.
public actor ModelArbiter {
    private var isHeld = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// Waits for its turn. For work the user already asked for, such as a transcription.
    public func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Takes the turn only if it is free. For optional work, such as a speed test.
    public func tryAcquire() -> Bool {
        guard !isHeld else { return false }
        isHeld = true
        return true
    }

    /// Waits for its turn, and gives up when the task is canceled.
    ///
    /// Someone in line can only leave by being served, so a canceled `acquire` could hold the caller for the length of
    /// a whole transcription. This never joins the line, and that is what a person pressing Stop needs.
    public func acquireCancelable(checkingEvery interval: Duration = .milliseconds(250)) async throws {
        while !tryAcquire() {
            try await Task.sleep(for: interval)
        }
    }

    public func release() {
        if waiting.isEmpty {
            isHeld = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}
