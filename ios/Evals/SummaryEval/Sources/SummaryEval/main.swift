import Domain
import Foundation
import LLMMLX
import NaturalLanguage
import TestSupport

// Usage: SummaryEval <model folder> <out.jsonl> [meetings=en,pt,ja,es|pt-long] [targets=auto,en,ja,pt,es] [templates=all|ids]

let args = CommandLine.arguments
let folder = URL(filePath: args[1])
let outPath = args[2]
let meetingFilter = args.count > 3 ? Set(args[3].split(separator: ",").map(String.init)) : nil
let targetList: [String?] = (args.count > 4 ? args[4] : "auto,en,ja,pt,es").split(separator: ",")
    .map { $0 == "auto" ? nil : String($0) }
let templateFilter = args.count > 5 && args[5] != "all" ? Set(args[5].split(separator: ",").map(String.init)) : nil

let model = ModelDescriptor(
    id: "qwen",
    displayName: "Qwen",
    roles: [.chat],
    runtime: .mlx,
    languages: ["en", "ja", "pt", "es"],
)
let engine = LoggingEngine(MLXLanguageEngine())
let arbiter = ModelArbiter()

let allMeetings = Meetings.short + [Meetings.longPortuguese]
let meetings = allMeetings.filter { m in meetingFilter?.contains(m.id) ?? Meetings.short.contains { $0.id == m.id } }
let templates = BuiltInTemplates.all.filter { templateFilter?.contains($0.id) ?? true }

struct ItemResult: Codable {
    let section: String
    let text: String
    let owner: String?
    let due: String?
    let time: Double?
    let needsReview: Bool
    let detected: String?
    let rightLanguage: Bool
    let copied: Bool
}

struct CaseResult: Codable {
    let meeting: String
    let target: String
    let template: String
    let seconds: Double
    let items: [ItemResult]
    let emptySections: [String]
    let error: String?
}

func detect(_ text: String) -> String? {
    let recognizer = NLLanguageRecognizer()
    recognizer.languageConstraints = [.english, .japanese, .portuguese, .spanish]
    recognizer.processString(text)
    return recognizer.dominantLanguage?.rawValue
}

func normalized(_ text: String) -> String {
    text.lowercased().filter { $0.isLetter || $0.isNumber }
}

/// A copy: most of the item's letters appear as one run in a transcript line, or the other way around.
func isCopy(_ text: String, of lines: [String]) -> Bool {
    let item = normalized(text)
    guard item.count >= 8 else { return false }
    return lines.contains { line in
        let source = normalized(line)
        return source.contains(item) || (item.contains(source) && source.count >= 8)
    }
}

func run(_ meeting: Meeting, target: String?, template: SummaryTemplate) async -> CaseResult {
    let store = FakeSummaryStore()
    let transcripts = FakeTranscriptStore()
    let speakerStore = FakeSpeakerStore()
    let id = RecordingID()
    var people: [String: Speaker] = [:]
    for line in meeting.lines where people[line.speaker] == nil {
        people[line.speaker] = Speaker(recordingID: id, number: people.count + 1, name: line.speaker)
    }
    let segments = meeting.lines.enumerated().map { index, line in
        TranscriptSegment(
            recordingID: id, start: Double(index) * 6, end: Double(index + 1) * 6, text: line.text,
            speaker: people[line.speaker]?.id.uuidString,
        )
    }
    try? await transcripts.append(
        segments,
        job: TranscriptionJob(recordingID: id, modelID: "probe", language: meeting.language),
    )
    // As the app does once transcription ends: the language that was detected is saved with the transcript.
    await transcripts.save(Transcript(recordingID: id, modelID: "probe", language: meeting.language, isComplete: true))
    await speakerStore.saveSpeakers(Array(people.values), assignments: [:], for: id)
    let coordinator = SummaryCoordinator(
        store: store, transcripts: transcripts, speakers: speakerStore, engine: engine, arbiter: arbiter,
        models: { $0 == model.id ? (model, folder) : nil },
    )
    let start = Date()
    var failure: String?
    do {
        try await coordinator.enqueue(id, template: template, modelID: model.id, language: target)
        while await !store.jobs.isEmpty {
            try await Task.sleep(for: .milliseconds(200))
        }
    } catch {
        failure = "\(error)"
    }
    let summary = await store.summaries(for: id).first
    let expected = target ?? meeting.language
    let speakers = Array(people.values)
    let texts = meeting.lines.map(\.text)
    var items: [ItemResult] = []
    for section in summary?.sections ?? [] {
        for item in section.items {
            let text = SpeakerTokens.decode(item.text, speakers: speakers)
            let lang = detect(text)
            items.append(ItemResult(
                section: section.title, text: text,
                owner: item.owner.map { SpeakerTokens.decode($0, speakers: speakers) }, due: item.due,
                time: item.sourceTime, needsReview: item.needsReview, detected: lang,
                rightLanguage: lang == expected, copied: isCopy(text, of: texts),
            ))
        }
    }
    return CaseResult(
        meeting: meeting.id, target: target ?? "auto", template: template.id,
        seconds: Date().timeIntervalSince(start), items: items,
        emptySections: (summary?.sections ?? []).filter(\.items.isEmpty).map(\.title),
        error: failure ?? (summary?.isComplete == true ? nil : "not finished"),
    )
}

FileManager.default.createFile(atPath: outPath, contents: nil)
let handle = try FileHandle(forWritingTo: URL(filePath: outPath))
let encoder = JSONEncoder()
encoder.outputFormatting = [.withoutEscapingSlashes]
var total = 0
var wrong = 0
var copied = 0
var review = 0
for meeting in meetings {
    for target in targetList {
        for template in templates {
            let result = await run(meeting, target: target, template: template)
            try handle.write(contentsOf: encoder.encode(result) + Data("\n".utf8))
            total += result.items.count
            wrong += result.items.count { !$0.rightLanguage }
            copied += result.items.count { $0.copied && (target ?? meeting.language) != meeting.language }
            review += result.items.count(where: \.needsReview)
            print(
                "\(meeting.id) -> \(target ?? "auto") \(template.id): \(result.items.count) items, " +
                    "\(result.items.count { !$0.rightLanguage }) wrong language, \(result.items.count(where: \.copied)) copied, " +
                    "\(result.items.count(where: \.needsReview)) review, \(Int(result.seconds))s \(result.error ?? "")",
            )
        }
    }
}

print("TOTAL items \(total), wrong language \(wrong), copied across languages \(copied), review \(review)")
