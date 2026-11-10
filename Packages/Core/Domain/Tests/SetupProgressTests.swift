@testable import Domain
import Foundation
import Testing

struct SetupProgressTests {
    private func model(
        _ id: String,
        role: ModelRole,
        size: Int64,
        runtime: ModelRuntime = .whisperKit,
    ) -> ModelDescriptor {
        let file = ModelFile(path: "weights", url: URL(fileURLWithPath: "/\(id)"), size: size, sha256: "")
        return ModelDescriptor(
            id: id, displayName: id, roles: [role], runtime: runtime,
            files: runtime == .appleSpeech ? [] : [file], languages: ["en"],
        )
    }

    private func snapshot(_ states: [String: InstallState]) -> ModelsSnapshot {
        let models = [
            model("speech-other", role: .transcription, size: 900),
            model("speech", role: .transcription, size: 600),
            model("chat", role: .chat, size: 300),
            model("voices", role: .speakerSeparation, size: 100),
            model("apple", role: .search, size: 0, runtime: .appleSpeech),
        ]
        var fits: [ModelRole: [ModelFit]] = [:]
        for model in models {
            // "speech-other" is a lesser fit for the same function, so it is not part of the setup.
            let label: FitLabel = model.id == "speech-other" ? .maySlow : .best
            fits[model.roles[0], default: []].insert(
                ModelFit(model: model, label: label, reason: .bestForDevice, speed: .unknown), at: 0,
            )
        }
        return ModelsSnapshot(
            device: DeviceProfile(name: "Phone", identifier: "phone", physicalMemoryMB: 8000),
            condition: DeviceCondition(),
            rightNow: .great,
            fits: fits,
            states: states,
            selections: [:],
            suggestions: [],
            priority: .balanced,
        )
    }

    @Test func `nothing on its way shows no progress`() {
        #expect(snapshot([:]).setupProgress == nil)
        #expect(snapshot(["speech": .ready, "chat": .failed(.unavailable)]).setupProgress == nil)
    }

    /// The bug this covers: after "Download all", the screen showed nothing while files arrived in the background.
    @Test func `downloads add up across the setup`() throws {
        let progress = try #require(snapshot([
            "speech": .downloading(received: 300, total: 600),
            "chat": .queued,
            "voices": .ready,
        ]).setupProgress)
        #expect(progress.received == 400)
        #expect(progress.total == 1000)
        #expect(progress.phase == .downloading)
        #expect(progress.fraction == 0.4)
    }

    @Test func `a finished model keeps counting, so the figure never goes back`() throws {
        let before = try #require(snapshot([
            "speech": .downloading(received: 590, total: 600),
            "chat": .downloading(received: 100, total: 300),
        ]).setupProgress)
        let after = try #require(snapshot([
            "speech": .verifying,
            "chat": .downloading(received: 100, total: 300),
        ]).setupProgress)
        #expect(after.fraction >= before.fraction)
    }

    @Test func `models iOS provides and models outside the setup are left out`() throws {
        #expect(snapshot(["apple": .preparing]).setupProgress == nil, "iOS provides this one")
        #expect(snapshot(["speech-other": .downloading(received: 1, total: 900)]).setupProgress == nil)
        let progress = try #require(snapshot([
            "speech": .downloading(received: 0, total: 600),
            "speech-other": .downloading(received: 1, total: 900),
            "apple": .preparing,
        ]).setupProgress)
        #expect(progress.total == 600)
    }

    @Test func `a failed model drops out of the figure`() throws {
        let progress = try #require(snapshot([
            "speech": .downloading(received: 300, total: 600),
            "chat": .failed(.unavailable),
        ]).setupProgress)
        #expect(progress.received == 300)
        #expect(progress.total == 600)
    }

    @Test func `queued with paused is still downloading, and an empty total is zero`() throws {
        let progress = try #require(snapshot([
            "speech": .paused(received: 100, total: 600),
            "chat": .queued,
        ]).setupProgress)
        #expect(progress.phase == .downloading)
        #expect(SetupProgress(received: 0, total: 0, phase: .downloading).fraction == 0)
    }

    @Test func `the phase says what is holding the setup`() throws {
        let paused = try #require(snapshot(["speech": .paused(received: 10, total: 600)]).setupProgress)
        #expect(paused.phase == .paused)
        let wifi = try #require(snapshot(["speech": .waitingForWiFi, "chat": .paused(received: 0, total: 300)])
            .setupProgress)
        #expect(wifi.phase == .waitingForWiFi)
        let finishing = try #require(snapshot(["speech": .preparing, "chat": .ready]).setupProgress)
        #expect(finishing.phase == .finishing)
        #expect(finishing.fraction == 1)
    }
}
