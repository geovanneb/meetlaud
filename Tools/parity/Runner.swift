// Runs the shared parity cases through the iOS app's Domain and prints what it returns (D-084).
//
// Built together with ios/Packages/Core/Domain/Sources by Tools/parity/run, so internal functions are reachable too.
// Tools/parity/golden.json is its output. The Android app's ParityTest runs the same cases through the Kotlin Domain
// and must produce exactly the same text, so the two apps behave the same for the same meeting.
//
// Every output is a string, built the same way in both languages: fields joined by " | ", lists by newlines, numbers
// with four decimals, nil as <nil>.

import Foundation

// MARK: - Reading the cases

struct Case: Decodable {
    let id: String
    let fn: String
    let args: [String: JSONValue]
}

enum JSONValue: Decodable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = try .object(container.decode([String: JSONValue].self))
        }
    }

    var string: String? { if case let .string(value) = self { value } else { nil } }
    var number: Double? { if case let .number(value) = self { value } else { nil } }
    var bool: Bool? { if case let .bool(value) = self { value } else { nil } }
    var array: [JSONValue] { if case let .array(value) = self { value } else { [] } }
    var object: [String: JSONValue] { if case let .object(value) = self { value } else { [:] } }

    /// Back to JSON, for types that decode themselves with Codable.
    var data: Data {
        try! JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed])
    }

    var any: Any {
        switch self {
        case let .string(value): value
        case let .number(value): value
        case let .bool(value): value
        case let .array(value): value.map(\.any)
        case let .object(value): value.mapValues(\.any)
        case .null: NSNull()
        }
    }
}

extension [String: JSONValue] {
    func string(_ key: String) -> String { self[key]?.string ?? "" }
    func optionalString(_ key: String) -> String? { self[key]?.string }
    func number(_ key: String) -> Double { self[key]?.number ?? 0 }
    func int(_ key: String) -> Int { Int(number(key)) }
    func bool(_ key: String) -> Bool { self[key]?.bool ?? false }
    func strings(_ key: String) -> [String] { (self[key]?.array ?? []).compactMap(\.string) }
}

// MARK: - Fixtures

let recording = RecordingID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)

func uuid(_ text: String) -> UUID { UUID(uuidString: text)! }

func segments(_ value: JSONValue?) -> [TranscriptSegment] {
    (value?.array ?? []).map { item in
        let o = item.object
        return TranscriptSegment(
            id: uuid(o.string("id")), recordingID: recording, start: o.number("start"), end: o.number("end"),
            text: o.string("text"), speaker: o.optionalString("speaker"),
        )
    }
}

func speakers(_ value: JSONValue?) -> [Speaker] {
    (value?.array ?? []).map { item in
        let o = item.object
        return Speaker(
            id: uuid(o.string("id")), recordingID: recording, number: o.int("number"), name: o.optionalString("name"),
            embedding: (o["embedding"]?.array ?? []).compactMap { $0.number.map(Float.init) }, talkTime: o.number("talkTime"),
        )
    }
}

func turns(_ value: JSONValue?) -> [SpeakerTurn] {
    (value?.array ?? []).map { item in
        let o = item.object
        return SpeakerTurn(
            speaker: o.string("speaker"), start: o.number("start"), end: o.number("end"),
            embedding: (o["embedding"]?.array ?? []).compactMap { $0.number.map(Float.init) },
        )
    }
}

func excerpts(_ value: JSONValue?) -> [AskExcerpt] {
    (value?.array ?? []).map { item in
        let o = item.object
        return AskExcerpt(
            recordingID: RecordingID(rawValue: uuid(o.string("recording"))), title: o.string("title"),
            time: o.number("time"), end: o["end"]?.number, text: o.string("text"),
        )
    }
}

func items(_ value: JSONValue?) -> [SummaryItem] {
    (value?.array ?? []).map { item in
        let o = item.object
        return SummaryItem(
            id: uuid(o.string("id")), text: o.string("text"), sourceTime: o["sourceTime"]?.number,
            owner: o.optionalString("owner"), due: o.optionalString("due"), isDone: o.bool("isDone"),
            needsReview: o.bool("needsReview"),
        )
    }
}

func kind(_ text: String) -> SectionKind { text == "tasks" ? .tasks : .bullets }

func summary(_ value: JSONValue?) -> Summary {
    let o = value?.object ?? [:]
    let sections = (o["sections"]?.array ?? []).map { section in
        let s = section.object
        return SummarySection(title: s.string("title"), kind: kind(s.string("kind")), items: items(s["items"]))
    }
    return Summary(
        id: uuid("22222222-2222-2222-2222-222222222222"), recordingID: recording, templateName: o.string("template"),
        modelID: "model", language: o.optionalString("language"), sections: sections, isComplete: true,
        createdAt: Date(timeIntervalSince1970: 0),
    )
}

func template(_ id: String) -> SummaryTemplate { BuiltInTemplates.all.first { $0.id == id }! }

// MARK: - Writing outputs

func f(_ value: Double?) -> String { value.map { String(format: "%.4f", $0) } ?? "<nil>" }
func f(_ value: Float) -> String { String(format: "%.4f", Double(value)) }
func s(_ value: String?) -> String { value ?? "<nil>" }

func show(_ request: LanguageRequest) -> String {
    "\(request.system)\n---\n\(request.prompt)\n---\(request.maxTokens) \(f(Double(request.temperature)))"
}

func show(_ item: SummaryItem) -> String {
    [item.text, f(item.sourceTime), s(item.owner), s(item.due), "\(item.isDone)", "\(item.needsReview)"]
        .joined(separator: " | ")
}

func show(_ citation: Citation) -> String {
    ["\(citation.number)", citation.recordingID.rawValue.uuidString, citation.recordingTitle, f(citation.time),
     citation.excerpt].joined(separator: " | ")
}

func show(_ node: MindMapNode, depth: Int = 0) -> String {
    let line = String(repeating: "  ", count: depth) + "\(node.id) | \(node.title) | \(f(node.time))"
    return ([line] + node.children.map { show($0, depth: depth + 1) }).joined(separator: "\n")
}

func label(_ label: FitLabel) -> String {
    switch label {
    case .unsupported: "unsupported"
    case .notRecommended: "notRecommended"
    case .maySlow: "maySlow"
    case .good: "good"
    case .best: "best"
    }
}

func reason(_ reason: FitReason) -> String {
    switch reason {
    case .bestForDevice: "bestForDevice"
    case .worksWell: "worksWell"
    case .belowTargetSpeed: "belowTargetSpeed"
    case .notEnoughMemory: "notEnoughMemory"
    case .unstableHere: "unstableHere"
    case let .languageNotCovered(language): "languageNotCovered(\(language))"
    }
}

func speed(_ speed: SpeedEvidence) -> String {
    switch speed {
    case let .estimated(low, high): "estimated(\(f(low)), \(f(high)))"
    case let .measured(value): "measured(\(f(value)))"
    case .unknown: "unknown"
    }
}

func rightNow(_ value: RightNow) -> String {
    func reason(_ reason: RightNow.Reason) -> String {
        switch reason {
        case .warm: "warm"
        case .hot: "hot"
        case .lowPower: "lowPower"
        case .lowBattery: "lowBattery"
        case .lowMemory: "lowMemory"
        }
    }
    return switch value {
    case .great: "great"
    case let .good(value): "good(\(reason(value)))"
    case let .limited(value): "limited(\(reason(value)))"
    case .paused: "paused"
    }
}

func thermal(_ text: String) -> ThermalLevel {
    switch text {
    case "fair": .fair
    case "serious": .serious
    case "critical": .critical
    default: .nominal
    }
}

func condition(_ o: [String: JSONValue]) -> DeviceCondition {
    DeviceCondition(
        thermal: thermal(o.string("thermal")), isLowPower: o.bool("isLowPower"), isCharging: o.bool("isCharging"),
        batteryLevel: o.number("batteryLevel"), availableMemoryMB: o.int("availableMemoryMB"),
        freeBytes: Int64(o.number("freeBytes")),
    )
}

func stats(_ value: JSONValue?) -> [ModelRunStat] {
    (value?.array ?? []).map { item in
        let o = item.object
        return ModelRunStat(
            modelID: o.string("modelID"), audioDuration: o.number("audioDuration"), wallTime: o.number("wallTime"),
            outcome: o.string("outcome") == "killed" ? .killed : .completed,
            date: Date(timeIntervalSince1970: o.number("date")),
        )
    }
}

// MARK: - Running

func run(_ c: Case) -> String {
    let a = c.args
    switch c.fn {
    case "markRepeats": return TranscriptCleanup.markRepeats(a.string("text"))
    case "hasWords": return "\(TranscriptCleanup.hasWords(a.string("text")))"
    case "vocabulary":
        let entries = (a["entries"]?.array ?? []).map { entry in
            let o = entry.object
            return VocabularyEntry(
                heard: o.string("heard"), written: o.string("written"),
                folderID: o.optionalString("folder").map { FolderID(rawValue: uuid($0)) },
            )
        }
        let folder = a.optionalString("folder").map { FolderID(rawValue: uuid($0)) }
        let applied = entries.applying(to: folder)
        return VocabularyCorrector.apply(applied, to: a.string("text")) + "\n" +
            TranscriptionHints.from(applied).joined(separator: "|")
    case "polish": return TranscriptPolish.polish(a.string("text"))
    case "languageWrong": return "\(LanguageCheck.isWrong(a.string("text"), for: a.string("language")))"
    case "queryTerms": return QueryTerms.terms(in: a.string("text")).joined(separator: "|")
    case "answerParse":
        let result = AnswerParser.parse(a.string("text"), excerpts: excerpts(a["excerpts"]))
        return ([result.body, "\(result.hasBasis)"] + result.citations.map(show)).joined(separator: "\n")
    case "answerVisible": return AnswerParser.visible(a.string("text"))
    case "copyingStart":
        let text = a.string("text")
        return AnswerParser.copyingStart(in: text).map { "\(text.utf16.distance(from: text.startIndex, to: $0))" }
            ?? "<nil>"
    case "claim": return CitationLocator.claim(citing: a.int("number"), in: a.string("body"))
    case "phrase":
        return s(CitationLocator.phrase(for: a.string("claim"), in: segments(a["segments"]))?.id.uuidString)
    case "memory": return s(MemoryCommand.text(in: a.string("text")))
    case "askPrompt":
        let history = (a["history"]?.array ?? []).enumerated().map { index, item in
            let o = item.object
            return ChatMessage(
                conversationID: uuid("33333333-3333-3333-3333-333333333333"),
                role: o.string("role") == "user" ? .user : .assistant, body: o.string("body"),
                state: AnswerState(rawValue: o.string("state")) ?? .complete,
                createdAt: Date(timeIntervalSince1970: Double(index)),
            )
        }
        let memories = a.strings("memories").map { MemoryItem(text: $0, createdAt: Date(timeIntervalSince1970: 0)) }
        return show(AskPrompts.answer(
            question: a.string("question"), excerpts: excerpts(a["excerpts"]), history: history, memories: memories,
            profile: a.optionalString("profile"), skill: a.optionalString("skill"),
        ))
    case "notesPrompt": return show(SummaryPrompts.notes(lines: a.strings("lines"), language: a.optionalString("language")))
    case "sectionPrompt":
        let t = template(a.string("template"))
        return show(SummaryPrompts.section(
            t.sections[a.int("section")], template: t, notes: a.strings("notes"),
            language: a.optionalString("language"), spoken: a.optionalString("spoken"),
            profile: a.optionalString("profile"), limit: a["limit"]?.number.map { Int($0) },
        ))
    case "translationPrompt":
        return show(SummaryPrompts.translation(a.strings("lines"), into: a.string("language"), names: a.strings("names")))
    case "draftPrompt":
        return show(SummaryPrompts.templateDraft(description: a.string("description"), language: a.optionalString("language")))
    case "summaryItems":
        return SummaryParser.items(from: a.string("text"), kind: kind(a.string("kind"))).map(show)
            .joined(separator: "\n")
    case "summaryNotes": return SummaryParser.notes(from: a.string("text")).joined(separator: "\n")
    case "balanced":
        let parts = (a["parts"]?.array ?? []).map { items($0) }
        return SummaryParser.balanced(parts, kind: kind(a.string("kind"))).map(show).joined(separator: "\n")
    case "summaryLine":
        return items(a["items"]).map { SummaryParser.line(for: $0, kind: kind(a.string("kind"))) }
            .joined(separator: "\n")
    case "validate":
        return items(a["items"]).map {
            show(SummaryValidator.validate(
                $0, segments: segments(a["segments"]), speakers: speakers(a["speakers"]),
                sameLanguage: a["sameLanguage"]?.bool ?? true,
            ))
        }.joined(separator: "\n")
    case "echoedExample":
        return items(a["items"]).map { "\(SummaryValidator.isEchoedExample($0, segments: segments(a["segments"])))" }
            .joined(separator: "\n")
    case "speakerTokens":
        let people = speakers(a["speakers"])
        let encoded = SpeakerTokens.encode(a.string("text"), speakers: people)
        let renamed = speakers(a["renamed"])
        return encoded + "\n" + SpeakerTokens.decode(encoded, speakers: renamed)
    case "parseDraft":
        guard let t = try? TemplateCodec.parseDraft(a.string("text")) else { return "invalid" }
        return ([t.name, t.instructions] + t.sections.map { "\($0.title) | \($0.kind.rawValue)" }).joined(separator: "\n")
    case "templateDecode":
        guard let t = try? TemplateCodec.decode(Data(a.string("text").utf8)) else { return "invalid" }
        return ([t.name, t.category.rawValue, t.instructions] + t.sections.map { "\($0.title) | \($0.kind.rawValue)" })
            .joined(separator: "\n")
    case "skillDecode":
        guard let skill = try? SkillCodec.decode(Data(a.string("text").utf8)) else { return "invalid" }
        return [skill.name, skill.summary, skill.instructions, "\(skill.isBuiltIn)"].joined(separator: "\n")
    case "exportTranscript":
        let format = TranscriptFormat(rawValue: a.string("format"))!
        return TranscriptExporter.text(
            title: a.string("title"), segments: segments(a["segments"]), speakers: speakers(a["speakers"]),
            format: format, options: ExportOptions(
                includesSpeakers: a["speakers_on"]?.bool ?? true, includesTimestamps: a["times_on"]?.bool ?? true,
            ),
        )
    case "exportSummary":
        return SummaryExporter.markdown(title: a.string("title"), summary: summary(a["summary"]), speakers: speakers(a["speakers"]))
    case "fileName": return ExportFileName.safe(a.string("title"), fileExtension: a.string("ext"))
    case "chunks":
        let people = speakers(a["speakers"])
        let all = segments(a["segments"])
        let chunks = KnowledgeChunker.chunks(segments: all, speakers: people, language: a.optionalString("language"))
        return ([KnowledgeChunker.sourceHash(segments: all, speakers: people)] +
            chunks.map { "\(f($0.start)) | \(f($0.end)) | \($0.text)" }).joined(separator: "\n")
    case "formatterLines":
        let lines = TranscriptFormatter.lines(segments: segments(a["segments"]), speakers: speakers(a["speakers"]))
        return TranscriptFormatter.chunks(lines, limit: a.int("limit")).map { $0.joined(separator: "\n") }
            .joined(separator: "\n===\n")
    case "tokens": return "\(TokenEstimator.tokens(in: a.string("text")))"
    case "rankFusion":
        let lists = (a["lists"]?.array ?? []).map { $0.array.compactMap { $0.string.map(uuid) } }
        return RankFusion.merge(lists, limit: a.int("limit")).map(\.uuidString).joined(separator: "\n")
    case "speakerStats":
        return SpeakerStats.compute(speakers: speakers(a["speakers"]), segments: segments(a["segments"])).map {
            "\($0.speakerID.uuidString) | \(f($0.talkTime)) | \(f($0.share)) | \($0.turns) | \(f($0.longestTurn))"
        }.joined(separator: "\n")
    case "alignment":
        let all = segments(a["segments"])
        let result = SpeakerAlignment.assign(segments: all, turns: turns(a["turns"]))
        return all.map { "\($0.id.uuidString) | \(s(result[$0.id]))" }.joined(separator: "\n")
    case "passingSounds":
        return SpeakerPipeline.withoutPassingSounds(turns(a["turns"]))
            .map { "\($0.speaker) | \(f($0.start)) | \(f($0.end))" }.joined(separator: "\n")
    case "centroid":
        return SpeakerPipeline.centroid(turns(a["turns"])).map(f).joined(separator: " ") + "\n" +
            (VoiceSeparation.closestPair(turns(a["turns"])).map { f(Double($0)) } ?? "<nil>") + "\n" +
            "\(VoiceSeparation.areDistinct(turns(a["turns"])))"
    case "voiceMatch":
        let embedding = a.strings("embedding").compactMap(Float.init)
        let prints = (a["prints"]?.array ?? []).map { item in
            let o = item.object
            return VoicePrint(
                personID: uuid(o.string("person")), modelID: "m",
                embedding: o.strings("embedding").compactMap(Float.init), talkTime: o.number("talkTime"),
            )
        }
        let match = switch VoiceMatcher.match(embedding, against: prints) {
        case let .suggested(person, score): "suggested | \(person.uuidString) | \(f(Double(score)))"
        case let .uncertain(person, score): "uncertain | \(person.uuidString) | \(f(Double(score)))"
        case .unknown: "unknown"
        }
        let blend = prints.count >= 2
            ? VoiceMatcher.blend(prints[0].embedding, weight: prints[0].talkTime, prints[1].embedding, weight: prints[1].talkTime)
            .map(f).joined(separator: " ")
            : ""
        return match + "\n" + blend
    case "recommend":
        let catalog = try! JSONDecoder().decode([ModelDescriptor].self, from: a["catalog"]!.data)
        let device = a["device"]!.object
        let context = RecommendationContext(
            device: DeviceProfile(
                name: "d", identifier: device.string("identifier"), physicalMemoryMB: device.int("memory"),
                probeScore: device.number("probe"),
            ),
            languages: a.strings("languages"),
            priority: Priority(rawValue: a.string("priority")) ?? .balanced,
            history: stats(a["history"]),
        )
        let engine = RecommendationEngine()
        var lines: [String] = []
        for role in ModelRole.allCases {
            for fit in engine.recommend(role: role, catalog: catalog, context: context) {
                lines.append("\(role.rawValue) | \(fit.model.id) | \(label(fit.label)) | \(reason(fit.reason)) | \(speed(fit.speed))")
            }
            let auto = engine.automaticModel(
                role: role, installed: catalog, language: a.strings("languages").first, context: context,
            )
            lines.append("\(role.rawValue) auto | \(s(auto?.id))")
        }
        let suggestions = AdvisorRules().suggestions(
            catalog: catalog, installedIDs: Set(a.strings("installed")), context: context,
            condition: condition(a["condition"]?.object ?? [:]), now: Date(timeIntervalSince1970: a.number("now")),
        )
        return (lines + suggestions.map(\.id)).joined(separator: "\n")
    case "rightNow":
        return rightNow(RightNow.evaluate(condition(a["condition"]!.object), requiredMemoryMB: a.int("required")))
    case "plan":
        let evidence: SpeedEvidence = switch a.string("speed") {
        case "measured": .measured(a.number("value"))
        case "estimated": .estimated(low: a.number("low"), high: a.number("high"))
        default: .unknown
        }
        let plan = TranscribePlan(
            duration: a.number("duration"), speed: evidence,
            rightNow: RightNow.evaluate(condition(a["condition"]!.object)), isCharging: a.bool("isCharging"),
        )
        return "\(plan.minutes.map { "\($0.lowerBound)...\($0.upperBound)" } ?? "<nil>") | \(plan.deservesNote) | \(plan.canWaitForCharger)"
    case "summaryParts":
        return SummaryParts.split(a.strings("notes"), duration: a.number("duration")).map { $0.joined(separator: "\n") }
            .joined(separator: "\n===\n")
    case "isQuestion": return "\(SectionGuide.isQuestion(a.string("text")))"
    case "languageName": return SummaryLanguage.name(of: a.string("code"))
    case "mindMap": return show(MindMapNode.tree(title: a.string("title"), summary: summary(a["summary"])))
    case "keptNames": return SummaryCoordinator.keptNames(speakers(a["speakers"]), in: a.optionalString("language")).joined(separator: "|")
    case "stableHash": return StableHash.hex(a.string("text"))
    case "transcriptionHints":
        let entries = a.strings("written").map { VocabularyEntry(heard: "x", written: $0) }
        return TranscriptionHints.from(entries).joined(separator: "|")
    case "sort":
        let items = a.strings("titles").enumerated().map { index, title in
            Recording(title: title, createdAt: Date(timeIntervalSince1970: Double(index)), duration: Double(index * 7 % 5))
        }
        return RecordingSort.allCases.map { sort in
            sort.rawValue + ": " + sort.sorted(items).map(\.title).joined(separator: " / ")
        }.joined(separator: "\n")
    default:
        return "unknown function \(c.fn)"
    }
}

@main
enum Runner {
    static func main() throws {
        let arguments = CommandLine.arguments
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
        var output: [[String: String]] = []
        for c in cases {
            output.append(["id": c.id, "output": run(c)])
        }
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: arguments[2]))
        print("parity: \(cases.count) cases")
    }
}
