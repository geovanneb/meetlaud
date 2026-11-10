@testable import Domain
import Foundation
import Testing
import TestSupport

/// What reaches the model, and what is left of its answer. Each case is one way a 2B model went wrong on a phone.
struct AskAnswerShapeTests {
    @Test func `a short meeting comes after its summary, so a broad question has something to stand on`()
        async throws
    {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello", "We move the launch to March"])
        await harness.summaries.save(Summary(
            recordingID: id, templateName: "Meeting", modelID: "llm", language: "en",
            sections: [SummarySection(title: "Topics", kind: .bullets, items: [
                SummaryItem(text: "Moving the launch", sourceTime: 10),
            ])],
            isComplete: true, createdAt: .now,
        ))
        await harness.language.setAnswers(["It was about moving the launch [1]."])

        let (message, _) = await harness.ask("What was it about?", scope: .recording(id))

        #expect(message?.state == .complete)
        #expect(message?.citations.first?.time == 10)
        let prompt = try #require(await harness.language.requests.first?.prompt)
        #expect(prompt.contains("[1] Summary, Topics: Moving the launch\n[2] Hello We move the launch to March"))
    }

    @Test func `when the model starts reciting its sources, the answer ends there`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello", "We move the launch to March"])
        await harness.language.setAnswers([
            "The launch moved to March [1].\n\n[1] Hello We move the launch to March\n[",
        ])

        let (message, updates) = await harness.ask("When is the launch?", scope: .recording(id))

        #expect(message?.state == .complete)
        #expect(message?.body == "The launch moved to March [1].")
        for case let .writing(text) in updates {
            #expect(!text.contains("Hello"))
        }
    }

    @Test func `an answer that only recites its sources is no answer`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello"])
        await harness.language.setAnswers(["[1] Hello\n[1] Hello"])

        let (message, _) = await harness.ask("What was said?", scope: .recording(id))

        #expect(message?.state == .noBasis)
    }

    @Test func `only real answers from earlier reach the model, without their old numbers`() async throws {
        let harness = AskHarness()
        let id = try await harness.addRecording(lines: ["Hello", "We move the launch to March"])
        let conversation = Conversation(scope: .recording(id), createdAt: .now)
        await harness.language.setAnswers(["NOT_FOUND", "The launch moved to March [1].", "In March [1]."])
        _ = await harness.ask("Who is Zed?", in: conversation)
        _ = await harness.ask("When is the launch?", in: conversation)

        _ = await harness.ask("And again?", in: conversation)

        let prompt = try #require(await harness.language.requests.last?.prompt)
        #expect(prompt.contains("You: The launch moved to March."))
        #expect(!prompt.contains("March [1]."))
        #expect(prompt.contains("Person: Who is Zed?"))
        #expect(!prompt.contains("You: \n"))
    }
}
