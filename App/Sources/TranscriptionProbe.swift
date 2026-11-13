#if DEBUG
    import AudioEditing
    import Domain
    import Foundation
    import UIKit

    struct TranscriptionProbeWindow: Codable {
        let start: Double
        let end: Double
        let segments: Int
        let lastSegmentEnd: Double?
        let seconds: Double
        let appState: String
        let error: String?
    }

    /// Does a long recording transcribe all the way through, also while the app is in the background?
    /// Runs only with `--transcribe-probe <recording id>` in debug builds. It reads the recording and runs the real
    /// engine, window by window, but saves nothing to the library: results go to Documents.
    enum TranscriptionProbe {
        static func run(
            id: RecordingID,
            services: Services,
            arbiter: ModelArbiter,
            modelID: String,
        ) async {
            guard let model = services.catalog.models.first(where: { $0.id == modelID }),
                  let engine = services.engines[model.runtime]
            else {
                write([], status: "no model \(modelID)")
                return
            }
            await arbiter.acquire()
            await services.lease.begin(title: "Probe")
            var results: [TranscriptionProbeWindow] = []
            write(results, status: "preparing")
            do {
                let started = Date()
                try await engine.prepare(model: model, folder: services.installer.folder(for: model.id))
                write(results, status: "prepared in \(Int(Date().timeIntervalSince(started))) s")
                let file = services.files.audioFile(for: id)
                let duration = try await SpeechWindowReader().duration(of: file)
                var language: String?
                // The same hints a real job gets, so the probe takes the path the app takes.
                let hints = TranscriptionHints.from(VocabularyPreferences.load())
                for try await window in SpeechWindowReader().windows(of: file, from: 0) {
                    let begin = Date()
                    var count = 0
                    var last: Double?
                    var failure: String?
                    do {
                        let result = try await engine.transcribe(window, language: language, hints: hints)
                        language = language ?? result.language
                        count = result.segments.count
                        last = result.segments.last.map { window.start + $0.end }
                    } catch {
                        failure = String(describing: error)
                    }
                    let state = await MainActor.run { Self.describe(UIApplication.shared.applicationState) }
                    results.append(TranscriptionProbeWindow(
                        start: window.start, end: window.end, segments: count, lastSegmentEnd: last,
                        seconds: Date().timeIntervalSince(begin), appState: state, error: failure,
                    ))
                    await services.lease.update(progress: duration > 0 ? window.end / duration : 0)
                    write(results, status: "running")
                }
                write(results, status: "done")
            } catch {
                write(results, status: "failed: \(error)")
            }
            await engine.unload()
            await services.lease.end()
            await arbiter.release()
        }

        private static func describe(_ state: UIApplication.State) -> String {
            switch state {
            case .active: "active"
            case .inactive: "inactive"
            case .background: "background"
            @unknown default: "unknown"
            }
        }

        private static func write(_ results: [TranscriptionProbeWindow], status: String) {
            guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            if let data = try? encoder.encode(results) {
                try? data.write(to: folder.appending(path: "transcribe-probe.json"), options: .atomic)
            }
            try? Data(status.utf8).write(to: folder.appending(path: "transcribe-probe.status"), options: .atomic)
        }
    }
#endif
