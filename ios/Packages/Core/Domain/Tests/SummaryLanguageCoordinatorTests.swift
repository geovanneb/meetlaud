@testable import Domain
import Foundation
import Testing
import TestSupport

private let model = ModelDescriptor(id: "llm", displayName: "LLM", roles: [.chat], runtime: .mlx, languages: ["en"])
private let template = SummaryTemplate(
    name: "Test", category: .general, instructions: "Summarize.",
    sections: [TemplateSection(title: "Key points"), TemplateSection(title: "Tasks", kind: .tasks)],
)

private struct Harness {
    let store = FakeSummaryStore()
    let transcripts = FakeTranscriptStore()
    let speakers = FakeSpeakerStore()
    let engine = ScriptedLanguageEngine()
    let coordinator: SummaryCoordinator
    let id = RecordingID()

    init() {
        coordinator = SummaryCoordinator(
            store: store, transcripts: transcripts, speakers: speakers, engine: engine,
            arbiter: ModelArbiter(), models: { $0 == "llm" ? (model, nil) : nil },
        )
    }

    /// A meeting in `spoken`, or in a language nobody detected.
    func addTranscript(
        spoken: String?,
        lines: Int = 2,
        text: String = "Ana disse que pede os orçamentos até sexta-feira.",
    ) async throws {
        let segments = (0 ..< lines).map { index in
            TranscriptSegment(recordingID: id, start: Double(index), end: Double(index) + 1, text: "\(text) \(index)")
        }
        try await transcripts.append(segments, job: TranscriptionJob(recordingID: id, modelID: "m", language: spoken))
        await transcripts.save(Transcript(recordingID: id, modelID: "m", language: spoken, isComplete: true))
    }

    func run(_ template: SummaryTemplate = template, language: String?) async throws -> Summary {
        try await coordinator.enqueue(id, template: template, modelID: "llm", language: language)
        for _ in 0 ..< 500 {
            if await store.jobs.isEmpty {
                break
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        return try #require(await store.summaries(for: id).first)
    }

    var sections: [LanguageRequest] {
        get async { await engine.requests.filter { $0.system.contains("You write one section") } }
    }

    var translations: [LanguageRequest] {
        get async { await engine.requests.filter { $0.system.contains("You translate lines") } }
    }
}

/// A summary asked for in one language, about a meeting held in another, and the checks on what the model wrote.
struct SummaryLanguageCoordinatorTests {
    @Test func `a summary in another language is written in the spoken one, then translated`() async throws {
        let harness = Harness()
        try await harness.addTranscript(spoken: "pt")
        await harness.engine.setSectionAnswers([
            "[1] Trocamos a pia e o fogão agora\n[1] A reforma completa fica para o ano que vem\n",
            "[1] Ana | Pede três orçamentos | sexta-feira\n",
        ])
        await harness.engine.setTranslations([
            "[1] シンクとコンロを今すぐ交換する\n[1] 全面改装は来年に回す\n",
            "[1] Ana | 見積もりを3件依頼する | 金曜日\n",
        ])
        let summary = try await harness.run(language: "ja")

        let sections = await harness.sections
        #expect(sections.allSatisfy { $0.system.contains("Write in Brazilian Portuguese") })
        #expect(sections.allSatisfy { !$0.system.contains("Japanese") })
        let translations = await harness.translations
        #expect(translations.count == 2, "One translation per section")
        #expect(translations[0].prompt.contains("[1] Trocamos a pia e o fogão agora\n[1] A reforma completa"))

        #expect(summary.sections[0].items.map(\.text) == ["シンクとコンロを今すぐ交換する", "全面改装は来年に回す"])
        #expect(summary.sections[0].items.allSatisfy { $0.sourceTime == 1 })
        let task = try #require(summary.sections[1].items.first)
        #expect(task.text == "見積もりを3件依頼する")
        #expect(task.owner == "Ana")
        #expect(task.due == "金曜日", "Checked against the transcript before translating, then translated")
    }

    @Test func `a date nobody said is gone before translation, and stays gone`() async throws {
        let harness = Harness()
        try await harness.addTranscript(spoken: "pt", text: "Ana pede os orçamentos.")
        await harness.engine.setSectionAnswers(["", "[1] Ana | Pede três orçamentos | sexta-feira\n"])
        await harness.engine.setTranslations(["[1] Ana | 見積もりを3件依頼する | 金曜日\n"])
        let summary = try await harness.run(language: "ja")
        #expect(summary.sections[1].items.first?.due == nil)
    }

    @Test(arguments: [nil, "pt"])
    func `a summary already in the right language is not translated`(_ language: String?) async throws {
        let harness = Harness()
        try await harness.addTranscript(spoken: "pt")
        await harness.engine.setSectionAnswers([
            "[1] Trocamos a pia e o fogão agora\n",
            "[1] Ana | Pede três orçamentos | sexta-feira\n",
        ])
        _ = try await harness.run(language: language)
        #expect(await harness.translations.isEmpty)
    }

    @Test func `a translation that loses a line is done again one line at a time`() async throws {
        let harness = Harness()
        try await harness.addTranscript(spoken: "pt", lines: 3)
        await harness.engine.setSectionAnswers([
            "[1] Trocamos a pia e o fogão agora\n[2] A reforma completa fica para o ano que vem\n",
            "",
        ])
        await harness.engine.setTranslations([
            "[1] シンクとコンロを今すぐ交換し、全面改装は来年に回す\n",
            "[1] シンクとコンロを今すぐ交換する\n",
            "[2] 全面改装は来年に回す\n",
        ])
        let summary = try await harness.run(language: "ja")

        #expect(await harness.translations.count == 3)
        let items = summary.sections[0].items
        #expect(items.map(\.text) == ["シンクとコンロを今すぐ交換する", "全面改装は来年に回す"])
        #expect(items.map(\.sourceTime) == [1, 2], "Each translation stays under its own citation")
    }

    @Test func `a line that cannot be translated is kept as it was`() async throws {
        let harness = Harness()
        try await harness.addTranscript(spoken: "pt")
        await harness.engine.setSectionAnswers(["[1] Trocamos a pia e o fogão agora\n", ""])
        await harness.engine.setTranslations([
            "[1] Trocamos a pia e o fogão agora\n",
            "[1] Trocamos a pia e o fogão agora\n",
        ])
        let summary = try await harness.run(language: "ja")
        #expect(summary.sections[0].items.map(\.text) == ["Trocamos a pia e o fogão agora"])
    }

    @Test func `a line that slips into another language is translated back`() async throws {
        let harness = Harness()
        try await harness.addTranscript(spoken: "ja", text: "佐藤：価格は九千五百円にします。")
        await harness.engine.setSectionAnswers(["[1] The price is set at 9,500 yen\n[1] 価格は9,500円\n", ""])
        await harness.engine.setTranslations(["[1] 価格は9,500円に決定した\n"])
        let summary = try await harness.run(language: nil)

        let translation = try #require(await harness.translations.first)
        #expect(translation.system.contains("into Japanese (日本語)"))
        #expect(translation.prompt.contains("The price is set"))
        #expect(!translation.prompt.contains("[1] 価格は9,500円\n"), "A line in the right language is left alone")
        #expect(summary.sections[0].items.map(\.text) == ["価格は9,500円に決定した", "価格は9,500円"])
    }

    @Test func `a translation keeps names already written in its script, and romanizes the others`() async throws {
        let harness = Harness()
        try await harness.addTranscript(spoken: "ja", text: "鈴木：資料を作ります。")
        await harness.speakers.saveSpeakers(
            [
                Speaker(recordingID: harness.id, number: 1, name: "鈴木"),
                Speaker(recordingID: harness.id, number: 2, name: "Ana"),
            ],
            assignments: [:], for: harness.id,
        )
        await harness.engine.setSectionAnswers(["[1] 鈴木が資料を作る\n", ""])
        await harness.engine.setTranslations(["[1] Suzuki vai preparar os materiais\n"])
        let summary = try await harness.run(language: "pt")

        let translation = try #require(await harness.translations.first)
        #expect(translation.system.contains("never translated: Ana."), "Listing 佐藤 made the model copy the line")
        #expect(summary.sections[0].items.first?.text == "Suzuki vai preparar os materiais")
    }

    @Test(arguments: [("ja", ["鈴木", "Ana"]), ("pt", ["Ana"]), ("en", ["Ana"])])
    func `names in another script are left for the model to romanize`(_ language: String, _ kept: [String]) {
        let id = RecordingID()
        let speakers = [
            Speaker(recordingID: id, number: 1, name: "鈴木"),
            Speaker(recordingID: id, number: 2, name: "Ana"),
        ]
        #expect(SummaryCoordinator.keptNames(speakers, in: language) == kept)
    }

    @Test func `with the spoken language unknown, the model writes in the one asked for`() async throws {
        let harness = Harness()
        try await harness.addTranscript(spoken: nil)
        await harness.engine.setSectionAnswers(["[1] シンクを交換する\n", ""])
        _ = try await harness.run(language: "ja")

        let sections = await harness.sections
        #expect(sections.allSatisfy { $0.system.contains("Write in Japanese (日本語), even if the transcript is") })
        #expect(await harness.translations.isEmpty)
    }

    @Test func `a long meeting keeps its notes and its summary in the spoken language until the end`() async throws {
        let harness = Harness()
        try await harness.addTranscript(spoken: "pt", lines: 400)
        _ = try await harness.run(language: "ja")

        let requests = await harness.engine.requests
        let notes = requests.filter { $0.system.contains("You take notes") }
        #expect(!notes.isEmpty)
        #expect(notes.allSatisfy { $0.system.contains("Write in Brazilian Portuguese") })
        #expect(await harness.sections.allSatisfy { $0.system.contains("Write in Brazilian Portuguese") })
        #expect(await harness.translations.allSatisfy { $0.system.contains("into Japanese (日本語)") })
    }

    @Test func `open questions keep only questions`() async throws {
        let harness = Harness()
        try await harness.addTranscript(spoken: "pt")
        let discussion = try #require(BuiltInTemplates.all.first { $0.id == "builtin.discussion" })
        await harness.engine.setSectionAnswers([
            "", "",
            """
            [1] Quem limpa a cozinha depois da obra?
            [1] Marina decidiu trocar a pia e o fogão agora.
            [1] A obra pode ser feita num fim de semana
            """,
        ])
        let summary = try await harness.run(discussion, language: nil)

        #expect(summary.sections[2].title == "Open questions")
        #expect(summary.sections[2].items.map(\.text) == ["Quem limpa a cozinha depois da obra?"])
        let request = try #require(await harness.sections.last)
        #expect(request.system.contains("Output one question per line, as: [seconds] question?"))
    }

    @Test func `an item that is only a speaker's name is dropped`() async throws {
        let harness = Harness()
        try await harness.addTranscript(spoken: "pt")
        await harness.speakers.saveSpeakers(
            [Speaker(recordingID: harness.id, number: 1, name: "Pedro")], assignments: [:], for: harness.id,
        )
        await harness.engine.setSectionAnswers(["[1] Pedro?\n[1] Pedro quer trocar a pia agora\n", ""])
        let summary = try await harness.run(language: nil)
        #expect(summary.sections[0].items.count == 1)
    }
}
