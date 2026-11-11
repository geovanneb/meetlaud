@testable import Domain
import Foundation
import Testing

private let codes = ["en", "ja", "pt", "es"]

/// One section of a built-in template, asked in one language about a meeting held in another (or the same).
struct PromptCase: CustomTestStringConvertible, Sendable {
    let template: SummaryTemplate
    let section: TemplateSection
    let target: String?
    let spoken: String

    var testDescription: String {
        "\(template.name) / \(section.title): \(spoken) → \(target ?? "auto")"
    }

    var expected: String {
        target ?? spoken
    }

    var request: LanguageRequest {
        SummaryPrompts.section(
            section, template: template, notes: ["[1] Ana: Hello."], language: target, spoken: spoken, profile: nil,
        )
    }
}

/// Every section of every built-in template, for every pair of spoken and requested language, plus "same as spoken".
private let promptCases: [PromptCase] = BuiltInTemplates.all.flatMap { template in
    template.sections.flatMap { section in
        codes.flatMap { spoken in
            ([nil] + codes).map { PromptCase(template: template, section: section, target: $0, spoken: spoken) }
        }
    }
}

struct SummaryLanguagePromptTests {
    @Test(arguments: promptCases)
    func `the prompt names the language to write in, at the start and at the end`(_ item: PromptCase) {
        let name = SummaryLanguage.name(of: item.expected)
        let request = item.request
        #expect(request.system.contains("Write in \(name)") || request.system.contains("you write in \(name)"))
        let lastLine = request.prompt.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        #expect(lastLine.contains(name), "The end of a prompt is what a small model follows best")
        #expect(!request.system.contains("code \(item.expected)"), "A small model ignores a language code")
    }

    @Test(arguments: promptCases)
    func `a summary in another language asks for a translation, and only then`(_ item: PromptCase) {
        let system = item.request.system
        if item.expected == item.spoken {
            #expect(!system.contains("Translate"))
        } else {
            #expect(system.contains("The transcript is in \(SummaryLanguage.name(of: item.spoken))"))
            #expect(system.contains("Translate what people said into \(SummaryLanguage.name(of: item.expected))"))
            #expect(system.contains("Never copy \(SummaryLanguage.name(of: item.spoken)) words"))
        }
    }

    @Test(arguments: BuiltInTemplates.all)
    func `every built-in section says what belongs in it`(_ template: SummaryTemplate) throws {
        for section in template.sections {
            let guide = try #require(SectionGuide.guide(for: section.title), "\(section.title) has no guide")
            let request = SummaryPrompts.section(
                section, template: template, notes: [], language: nil, spoken: "en", profile: nil,
            )
            #expect(request.system.contains(guide))
            #expect(request.prompt.contains(guide))
        }
        let guides = template.sections.compactMap { SectionGuide.guide(for: $0.title) }
        #expect(Set(guides).count == guides.count, "Two sections asking for the same thing get the same items")
    }

    @Test(arguments: BuiltInTemplates.all)
    func `sections in a list never copy the transcript line by line`(_ template: SummaryTemplate) {
        for section in template.sections where section.kind == .bullets {
            let system = SummaryPrompts.section(
                section, template: template, notes: [], language: "ja", spoken: "pt", profile: nil,
            ).system
            #expect(system.contains("Never start an item with a speaker's name and a colon"))
            #expect(system.contains("never repeat or translate the transcript line by line"))
        }
    }

    @Test(arguments: [("ja", "[120] 佐藤 | 報告書を送る | 金曜日"), ("pt", "[120] Ana | Enviar o relatório | sexta-feira"),
                      ("es", "[120] Ana | Enviar el informe | viernes"), (
                          "en",
                          "[120] Ana | Send the report | Friday",
                      )])
    func `the task example is in the language of the summary`(_ target: String, _ example: String) {
        let section = TemplateSection(title: "Action items", kind: .tasks)
        let request = SummaryPrompts.section(
            section, template: BuiltInTemplates.all[0], notes: [], language: target, spoken: "en", profile: nil,
        )
        #expect(request.system.contains("like this example: \(example)"))
    }

    @Test func `a task copied from the example is dropped, unless the meeting was about it`() {
        let copied = SummaryItem(text: "報告書を送る", sourceTime: 1, owner: "佐藤")
        let unrelated = [TranscriptSegment(recordingID: RecordingID(), start: 0, end: 1, text: "Vamos trocar a pia.")]
        #expect(SummaryValidator.isEchoedExample(copied, segments: unrelated))
        let real = SummaryItem(text: "Send the report", sourceTime: 1, owner: "Ana")
        let said = [TranscriptSegment(recordingID: RecordingID(), start: 0, end: 1, text: "I will send the report.")]
        #expect(!SummaryValidator.isEchoedExample(real, segments: said))
        #expect(!SummaryValidator.isEchoedExample(SummaryItem(text: "Send the budget"), segments: unrelated))
    }

    @Test func `a section of a person's own template works without a guide`() {
        let template = SummaryTemplate(
            name: "Mine", category: .general, instructions: "Focus on risks.",
            sections: [TemplateSection(title: "Risks we see")],
        )
        let request = SummaryPrompts.section(
            template.sections[0], template: template, notes: [], language: "es", spoken: "en", profile: nil,
        )
        #expect(request.system.contains("This section is Risks we see."))
        #expect(request.system.contains("Focus on risks."))
        #expect(request.system.contains("Spanish (español)"))
    }

    @Test func `an unknown spoken language still gets a clear target`() {
        let section = TemplateSection(title: "Key points")
        let request = SummaryPrompts.section(
            section, template: BuiltInTemplates.all[0], notes: [], language: "ja", spoken: nil, profile: nil,
        )
        #expect(request.system.contains("Write in Japanese (日本語), even if the transcript is in another language"))
    }

    @Test func `with nothing known, the model follows the transcript`() {
        let section = TemplateSection(title: "Key points")
        let request = SummaryPrompts.section(
            section, template: BuiltInTemplates.all[0], notes: [], language: nil, spoken: nil, profile: nil,
        )
        #expect(request.system.contains("Write in the same language as the transcript."))
    }

    @Test(arguments: [
        ("en", "English"), ("ja", "Japanese (日本語)"), ("pt", "Brazilian Portuguese (português do Brasil)"),
        ("es", "Spanish (español)"), ("fr", "French"),
    ])
    func `languages have names a model understands`(_ code: String, _ name: String) {
        #expect(SummaryLanguage.name(of: code) == name)
    }

    @Test(arguments: codes)
    func `notes stay in the language that was spoken`(_ spoken: String) {
        let system = SummaryPrompts.notes(lines: ["[1] Ana: Hi"], language: spoken).system
        #expect(system.contains("Write in \(SummaryLanguage.name(of: spoken)), the language of the transcript."))
        #expect(!system.contains("Translate"))
    }

    @Test(arguments: codes)
    func `a translation keeps citations, columns, names, and the number of lines`(_ target: String) {
        let request = SummaryPrompts.translation(["[5] Ana | Envia o relatório | sexta-feira"], into: target)
        #expect(request.system.contains("into \(SummaryLanguage.name(of: target))"))
        #expect(request.system.contains("same number of lines"))
        #expect(request.system.contains("Keep [seconds]"))
        #expect(request.system.contains("| separators"))
        #expect(request.prompt.contains("[5] Ana | Envia o relatório | sexta-feira"))
        #expect(request.prompt.hasSuffix("Translate into \(SummaryLanguage.name(of: target))."))
    }

    @Test func `a translation keeps the names it is given, and every currency`() {
        let system = SummaryPrompts.translation(["[1] x"], into: "ja", names: ["鈴木", "Ana"]).system
        #expect(system.contains("Write these names exactly like this, never translated: 鈴木, Ana."))
        #expect(system.contains("8,000 reais stays 8,000 reais"))
        #expect(!SummaryPrompts.translation(["[1] x"], into: "ja").system.contains("these names"))
    }

    @Test(arguments: BuiltInTemplates.all)
    func `only open questions are asked for as questions`(_ template: SummaryTemplate) {
        for section in template.sections {
            let system = SummaryPrompts.section(
                section, template: template, notes: [], language: nil, spoken: "en", profile: nil,
            ).system
            let asks = system.contains("Output one question per line, as: [seconds] question?")
            #expect(asks == (section.title == "Open questions"), "\(section.title)")
        }
    }

    @Test(arguments: [
        ("Who cleans the kitchen after the work?", true), ("¿Abre el aparcamiento los domingos?", true),
        ("パートの方も対象にするのか", true), ("古いデータを移すのか。", true), ("誰が掃除しますか？", true),
        ("Marina decidiu trocar a pia.", false), ("導入は五月一日から。", false), ("Canada stays open", false),
    ])
    func `a question is recognized in every language`(_ text: String, _ isQuestion: Bool) {
        #expect(SectionGuide.isQuestion(text) == isQuestion)
    }

    @Test func `a template draft is written in the person's language`() {
        #expect(SummaryPrompts.templateDraft(description: "x", language: "ja").system.contains("Write in Japanese"))
        #expect(SummaryPrompts.templateDraft(description: "x", language: nil).system
            .contains("language of the request"))
    }
}

struct LanguageCheckTests {
    @Test(arguments: [
        // Right language
        ("佐藤さんが来週金曜日までに説明会の資料を作る", "ja"),
        ("Marinaさんが8,000 reaisの予算を承認した", "ja"),
        ("The launch moves to March 24, and features freeze on March 10", "en"),
        ("佐藤 will send the slides by Friday", "en"),
        ("Trocamos a pia e o fogão agora, com limite de oito mil reais", "pt"),
        ("Abrimos los domingos desde el uno de junio con dos personas nuevas", "es"),
        // Too little to tell
        ("2026", "ja"),
        ("Ana", "en"),
        ("Março", "es"),
    ])
    func `a line in the right language, or too short to tell, passes`(_ text: String, _ language: String) {
        #expect(!LanguageCheck.isWrong(text, for: language))
    }

    @Test(arguments: [
        ("Trocamos a pia e o fogão agora, com limite de oito mil reais", "ja"),
        ("Bruno sends the fix plan by Friday", "ja"),
        ("価格は九千五百円に決定", "en"),
        ("参加者は、新しい服を着ることを歓迎した。", "pt"),
        ("The launch moves to March 24 and the team will test it", "pt"),
        ("O lançamento foi adiado e a equipe não muda", "en"),
        ("Ana: Sim, nisso eu concordo totalmente.", "en"),
        ("Abrimos los domingos desde el uno de junio con dos personas nuevas", "pt"),
        ("Abrimos os domingos a partir de junho, com duas pessoas e um gerente", "es"),
    ])
    func `a line in another language is caught`(_ text: String, _ language: String) {
        #expect(LanguageCheck.isWrong(text, for: language))
    }
}
