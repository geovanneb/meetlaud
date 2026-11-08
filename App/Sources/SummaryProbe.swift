#if DEBUG
    import Domain
    import Foundation
    import TestSupport

    struct SummaryProbeResult: Codable {
        let label: String
        let lines: Int
        let estimatedTokens: Int
        let seconds: Double
        let lowestAvailableMemoryMB: Int
        let thermalStart: Int
        let thermalEnd: Int
        let notNeedingReview: Int
        let needingReview: Int
        let output: String
        let error: String?
    }

    /// F5: does the real summary pipeline hold up on this phone, on meetings of 1 and 3 hours?
    /// Runs only with `--summary-probe` in debug builds, on invented meetings, and writes to Documents.
    enum SummaryProbe {
        private struct Case {
            let label: String
            let language: String?
            let lines: [(speaker: String, text: String)]
        }

        private static func parse(_ text: String, separator: Character) -> [(speaker: String, text: String)] {
            text.split(whereSeparator: \.isNewline).compactMap { line in
                let parts = line.split(separator: separator, maxSplits: 1)
                guard parts.count == 2 else { return nil }
                return (String(parts[0]), parts[1].trimmingCharacters(in: .whitespaces))
            }
        }

        /// A long meeting with facts that can be checked: every project has a budget, an owner, and a date.
        private static func longMeeting(minutes: Int) -> [(speaker: String, text: String)] {
            let people = ["Ana", "Bruno", "Carla", "Diego"]
            var lines: [(speaker: String, text: String)] = []
            var project = 1
            while lines.count < minutes * 10 {
                let owner = people[project % people.count]
                let other = people[(project + 1) % people.count]
                let lead = people[(project + 2) % people.count]
                lines += [
                    (lead, "Next item is project \(project). Where do we stand on it?"),
                    (
                        other,
                        "Project \(project) is on track, but prices went up \(project % 9 + 2) percent.",
                    ),
                    (lead, "How much of the budget of \(project * 1000) dollars is already spent?"),
                    (
                        other,
                        "About half. We still have the second phase to pay for, and that part worries me a little.",
                    ),
                    (owner, "I talked to the supplier last week, and they will not move on price this year."),
                    (lead, "Then we accept the new price, and we take the difference from the reserve."),
                    (other, "I can live with that as long as finance agrees before the end of the month."),
                    (
                        lead,
                        "Agreed. \(owner) sends the revised plan for project \(project) by day \(project % 28 + 1).",
                    ),
                    (owner, "Sure, I will send the revised plan for project \(project) by then."),
                    (other, "Good. I have nothing else on this one, so we can move on to the next item."),
                ]
                project += 1
            }
            return lines
        }

        private static let cases = [
            Case(label: "pt-BR short", language: "pt", lines: parse(LanguageProbe.portuguese, separator: ":")),
            Case(label: "en short", language: "en", lines: parse(LanguageProbe.english, separator: ":")),
            Case(label: "ja short", language: "ja", lines: parse(LanguageProbe.japanese, separator: "：")),
            Case(label: "en 1 hour", language: "en", lines: longMeeting(minutes: 60)),
            Case(label: "en 3 hours", language: "en", lines: longMeeting(minutes: 180)),
        ]

        static func run(
            engine: any LanguageModelEngine,
            arbiter: ModelArbiter,
            model: ModelDescriptor,
            folder: URL?,
            device: any DeviceMonitor,
        ) async {
            var results: [SummaryProbeResult] = []
            write(results, status: "running")
            for item in cases {
                write(results, status: "running \(item.label)")
                await results.append(run(item, on: Runtime(
                    engine: engine, arbiter: arbiter, model: model, folder: folder, device: device,
                )))
                write(results, status: "running")
            }
            write(results, status: "done")
        }

        private struct Runtime {
            let engine: any LanguageModelEngine
            let arbiter: ModelArbiter
            let model: ModelDescriptor
            let folder: URL?
            let device: any DeviceMonitor
        }

        private static func run(_ item: Case, on runtime: Runtime) async -> SummaryProbeResult {
            let (engine, arbiter, model, folder, device) = (
                runtime.engine, runtime.arbiter, runtime.model, runtime.folder, runtime.device,
            )
            let store = FakeSummaryStore()
            let transcripts = FakeTranscriptStore()
            let speakerStore = FakeSpeakerStore()
            let id = RecordingID()
            await fill(item, id: id, transcripts: transcripts, speakers: speakerStore)
            let queue = SummaryCoordinator(
                store: store, transcripts: transcripts, speakers: speakerStore, engine: engine, arbiter: arbiter,
                models: { $0 == model.id ? (model, folder) : nil },
            )
            let thermalStart = await device.condition().thermal.rawValue
            var lowest = await device.condition().availableMemoryMB
            let start = Date()
            var failure: String?
            do {
                try await queue.enqueue(
                    id,
                    template: BuiltInTemplates.all[0],
                    modelID: model.id,
                    language: item.language,
                )
                while await !store.jobs.isEmpty {
                    try await Task.sleep(for: .seconds(1))
                    lowest = await min(lowest, device.condition().availableMemoryMB)
                }
            } catch {
                failure = "\(error)"
            }
            let summary = await store.summaries(for: id).first
            let items = summary?.sections.flatMap(\.items) ?? []
            let people = await speakerStore.speakers(for: id)
            return await SummaryProbeResult(
                label: item.label,
                lines: item.lines.count,
                estimatedTokens: item.lines.reduce(0) { $0 + TokenEstimator.tokens(in: $1.text) },
                seconds: Date().timeIntervalSince(start),
                lowestAvailableMemoryMB: lowest,
                thermalStart: thermalStart,
                thermalEnd: device.condition().thermal.rawValue,
                notNeedingReview: items.count { !$0.needsReview },
                needingReview: items.count(where: \.needsReview),
                output: text(of: summary, speakers: people),
                error: failure ?? (summary?.isComplete == true ? nil : "not finished"),
            )
        }

        private static func fill(
            _ item: Case,
            id: RecordingID,
            transcripts: FakeTranscriptStore,
            speakers: FakeSpeakerStore,
        ) async {
            var people: [String: Speaker] = [:]
            for line in item.lines where people[line.speaker] == nil {
                people[line.speaker] = Speaker(
                    recordingID: id, number: people.count + 1, name: line.speaker,
                )
            }
            let segments = item.lines.enumerated().map { index, line in
                TranscriptSegment(
                    recordingID: id, start: Double(index) * 6, end: Double(index + 1) * 6, text: line.text,
                    speaker: people[line.speaker]?.id.uuidString,
                )
            }
            let job = TranscriptionJob(recordingID: id, modelID: "probe", language: item.language)
            try? await transcripts.append(segments, job: job)
            await speakers.saveSpeakers(Array(people.values), assignments: [:], for: id)
        }

        private static func text(of summary: Summary?, speakers: [Speaker]) -> String {
            var lines: [String] = []
            for section in summary?.sections ?? [] {
                lines.append("## \(section.title)")
                for item in section.items {
                    let owner = item.owner.map { SpeakerTokens.decode($0, speakers: speakers) } ?? "-"
                    let due = item.due ?? "-"
                    let time = item.sourceTime.map { "[\(Int($0))]" } ?? "[none]"
                    let flag = item.needsReview ? " (REVIEW)" : ""
                    let text = SpeakerTokens.decode(item.text, speakers: speakers)
                    lines
                        .append(section
                            .kind == .tasks ? "\(time) \(owner) | \(text) | \(due)\(flag)" : "\(time) \(text)\(flag)")
                }
            }
            return lines.joined(separator: "\n")
        }

        private static func write(_ results: [SummaryProbeResult], status: String) {
            guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            if let data = try? encoder.encode(results) {
                try? data.write(to: folder.appending(path: "summary-probe.json"), options: .atomic)
            }
            try? Data(status.utf8).write(to: folder.appending(path: "summary-probe.status"), options: .atomic)
        }
    }
#endif
