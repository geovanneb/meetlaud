@testable import Domain
import Foundation
import Testing

private func model(
    _ id: String,
    memory: Int = 1000,
    languages: [String] = ["en", "ja", "pt", "es"],
    quality: Int = 3,
    reference: [ReferenceSpeed] = [],
    size: Int64 = 100,
    roles: [ModelRole] = [.transcription],
) -> ModelDescriptor {
    ModelDescriptor(
        id: id,
        displayName: id,
        roles: roles,
        runtime: .whisperKit,
        files: [ModelFile(path: "a", url: URL(fileURLWithPath: "/a"), size: size, sha256: "x")],
        languages: languages,
        minMemoryMB: memory,
        quality: Dictionary(uniqueKeysWithValues: languages.map { ($0, quality) }),
        reference: reference,
    )
}

private let iPhone17 = DeviceProfile(name: "iPhone 17", identifier: "iPhone18,3", physicalMemoryMB: 8000)

private func run(
    _ id: String,
    speed: Double = 10,
    outcome: ModelRunStat.Outcome = .completed,
    daysAgo: Double = 0,
) -> ModelRunStat {
    ModelRunStat(
        modelID: id,
        audioDuration: speed * 100,
        wallTime: 100,
        outcome: outcome,
        date: Date(timeIntervalSince1970: 1_000_000 - daysAgo * 86400),
    )
}

struct RecommendationEngineTests {
    private let engine = RecommendationEngine()

    private func recommend(
        _ catalog: [ModelDescriptor],
        device: DeviceProfile = iPhone17,
        languages: [String] = ["en"],
        priority: Priority = .balanced,
        history: [ModelRunStat] = [],
        role: ModelRole = .transcription,
    ) -> [ModelFit] {
        engine.recommend(
            role: role,
            catalog: catalog,
            context: RecommendationContext(
                device: device, languages: languages, priority: priority, history: history,
            ),
        )
    }

    @Test func `the top model is marked best`() {
        let fits = recommend([model("a", quality: 3), model("b", quality: 5)])
        #expect(fits.first?.model.id == "b")
        #expect(fits.first?.label == .best)
        #expect(fits.last?.label == .good)
    }

    @Test func `only models for the role appear`() {
        let fits = recommend([model("a"), model("chat", roles: [.chat])])
        #expect(fits.map(\.model.id) == ["a"])
    }

    @Test func `a model bigger than the device is unsupported`() {
        let fit = recommend([model("huge", memory: 16000)]).first
        #expect(fit?.label == .unsupported)
        #expect(fit?.reason == .notEnoughMemory)
    }

    @Test func `a model near the memory limit is not recommended`() {
        #expect(recommend([model("tight", memory: 6000)]).first?.label == .notRecommended)
    }

    @Test func `a language the model lacks is not recommended, and names the language`() {
        let fit = recommend([model("eu", languages: ["en", "es"])], languages: ["ja"]).first
        #expect(fit?.label == .notRecommended)
        #expect(fit?.reason == .languageNotCovered("ja"))
    }

    @Test func `the language decides the winner`() {
        let europe = model("eu", languages: ["en", "es"], quality: 5)
        let all = model("all", quality: 3)
        #expect(recommend([europe, all], languages: ["ja"]).first?.model.id == "all")
        #expect(recommend([europe, all], languages: ["es"]).first?.model.id == "eu")
    }

    @Test func `a measured speed replaces the estimate`() {
        let reference = [ReferenceSpeed(device: "iPhone18,3", speedX: 20, peakMemoryMB: 500, probeScore: 100)]
        let fit = recommend([model("a", reference: reference)], history: [run("a", speed: 2)]).first
        #expect(fit?.speed == .measured(2))
        #expect(fit?.label == .maySlow)
    }

    @Test func `the latest measurement wins`() {
        let history = [run("a", speed: 2, daysAgo: 5), run("a", speed: 8, daysAgo: 1)]
        #expect(recommend([model("a")], history: history).first?.speed == .measured(8))
    }

    @Test func `estimates are a range scaled by the probe`() throws {
        let reference = [ReferenceSpeed(device: "iPhone18,3", speedX: 10, peakMemoryMB: 500, probeScore: 100)]
        var device = iPhone17
        device.identifier = "other"
        device.probeScore = 50
        let fit = try #require(recommend([model("a", reference: reference)], device: device).first)
        guard case let .estimated(low, high) = fit.speed else {
            Issue.record("Expected an estimate")
            return
        }
        #expect(abs(low - 3.5) < 0.001)
        #expect(abs(high - 6.5) < 0.001)
    }

    @Test func `no data means no speed claim`() {
        #expect(recommend([model("a")]).first?.speed == .unknown)
    }

    @Test func `two kills mark a model unstable`() {
        let history = [run("a", outcome: .killed), run("a", outcome: .killed, daysAgo: 1)]
        let fit = recommend([model("a"), model("b")], history: history).last
        #expect(fit?.model.id == "a")
        #expect(fit?.reason == .unstableHere)
    }

    @Test func `one kill is not enough to judge`() {
        #expect(recommend([model("a")], history: [run("a", outcome: .killed)]).first?.label == .best)
    }

    @Test func `priority changes the winner`() {
        let fast = model("fast", quality: 3, reference: [
            ReferenceSpeed(device: "iPhone18,3", speedX: 30, peakMemoryMB: 500, probeScore: 0),
        ])
        let good = model("good", quality: 5, reference: [
            ReferenceSpeed(device: "iPhone18,3", speedX: 5, peakMemoryMB: 500, probeScore: 0),
        ])
        #expect(recommend([fast, good], priority: .speed).first?.model.id == "fast")
        #expect(recommend([fast, good], priority: .quality).first?.model.id == "good")
    }

    @Test func `smaller wins a tie`() {
        let fits = recommend([model("big", size: 2_000_000_000), model("small", size: 200_000_000)])
        #expect(fits.first?.model.id == "small")
    }

    @Test func `the same input always gives the same order`() {
        let catalog = [model("a"), model("b", quality: 4), model("c", memory: 7000)]
        #expect(recommend(catalog) == recommend(catalog))
    }

    @Test func `automatic mode only picks installed models that speak the language`() {
        let europe = model("eu", languages: ["en"], quality: 5)
        let all = model("all", quality: 3)
        let picked = engine.automaticModel(
            role: .transcription,
            installed: [europe, all],
            language: "ja",
            context: RecommendationContext(device: iPhone17, languages: [], priority: .balanced, history: []),
        )
        #expect(picked?.id == "all")
    }

    @Test func `automatic mode returns nothing rather than a bad fit`() {
        let picked = engine.automaticModel(
            role: .transcription,
            installed: [model("eu", languages: ["en"])],
            language: "ja",
            context: RecommendationContext(device: iPhone17, languages: [], priority: .balanced, history: []),
        )
        #expect(picked == nil)
    }
}

struct RightNowTests {
    @Test(arguments: [
        (DeviceCondition(), RightNow.great),
        (DeviceCondition(thermal: .fair), .good(.warm)),
        (DeviceCondition(thermal: .serious), .limited(.hot)),
        (DeviceCondition(thermal: .critical), .paused),
        (DeviceCondition(isLowPower: true), .limited(.lowPower)),
        (DeviceCondition(isCharging: false, batteryLevel: 0.25), .good(.lowBattery)),
        (DeviceCondition(isCharging: false, batteryLevel: 0.1), .limited(.lowBattery)),
        (DeviceCondition(isCharging: true, batteryLevel: 0.1), .great),
    ])
    func `conditions map to a status`(condition: DeviceCondition, expected: RightNow) {
        #expect(RightNow.evaluate(condition) == expected)
    }

    @Test func `heat outranks everything`() {
        let condition = DeviceCondition(thermal: .critical, isLowPower: true)
        #expect(RightNow.evaluate(condition) == .paused)
        #expect(!RightNow.evaluate(condition).allowsHeavyWork)
    }

    @Test func `not enough memory for the job limits it`() {
        let condition = DeviceCondition(availableMemoryMB: 500)
        #expect(RightNow.evaluate(condition, requiredMemoryMB: 1000) == .limited(.lowMemory))
    }
}

struct AdvisorRulesTests {
    private let rules = AdvisorRules()
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func suggestions(
        catalog: [ModelDescriptor],
        installed: Set<String>,
        condition: DeviceCondition = DeviceCondition(),
        languages: [String] = ["en"],
        history: [ModelRunStat] = [],
    ) -> [AdvisorSuggestion] {
        rules.suggestions(
            catalog: catalog,
            installedIDs: installed,
            context: RecommendationContext(
                device: iPhone17, languages: languages, priority: .balanced, history: history,
            ),
            condition: condition,
            now: now,
        )
    }

    @Test func `nothing to say when the best model is installed`() {
        #expect(suggestions(catalog: [model("a", quality: 5), model("b")], installed: ["a"]).isEmpty)
    }

    @Test func `suggests a better fit`() {
        let result = suggestions(catalog: [model("a"), model("b", quality: 5)], installed: ["a"])
        #expect(result == [.betterFit(role: .transcription, modelID: "b")])
    }

    @Test func `flags a language the installed models miss`() {
        let result = suggestions(
            catalog: [model("eu", languages: ["en"]), model("all")], installed: ["eu"], languages: ["ja"],
        )
        #expect(result.contains(.languageNotCovered(language: "ja", role: .transcription)))
    }

    @Test func `flags repeated kills, with a smaller alternative`() {
        let history = [run("big", outcome: .killed), run("big", outcome: .killed, daysAgo: 1)]
        let result = suggestions(
            catalog: [model("big", memory: 3000), model("small", memory: 1000)],
            installed: ["big"],
            history: history,
        )
        #expect(result.contains(.unstable(modelID: "big", alternativeID: "small")))
    }

    @Test func `flags a model slower than real time`() {
        let result = suggestions(catalog: [model("a")], installed: ["a"], history: [run("a", speed: 0.5)])
        #expect(result.contains(.tooSlow(modelID: "a")))
    }

    @Test func `suggests removing an unused model only when space is tight`() {
        let old = [run("a", daysAgo: 90)]
        let tight = DeviceCondition(freeBytes: 1_000_000_000)
        #expect(suggestions(catalog: [model("a")], installed: ["a"], history: old).isEmpty)
        #expect(suggestions(catalog: [model("a")], installed: ["a"], condition: tight, history: old)
            .contains(.unusedModel(modelID: "a", bytes: 100)))
    }

    @Test func `a recently used model is never flagged as unused`() {
        let tight = DeviceCondition(freeBytes: 1_000_000_000)
        let result = suggestions(catalog: [model("a")], installed: ["a"], condition: tight, history: [run("a")])
        #expect(result.isEmpty)
    }
}
