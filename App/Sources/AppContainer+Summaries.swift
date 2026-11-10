import Domain
import FeatureRecording
import Foundation
import UIKit

extension AppContainer {
    static func makeSummaryQueue(
        services: Services,
        arbiter: ModelArbiter,
        gate: GenerationGate,
    ) -> SummaryCoordinator {
        let catalog = services.catalog
        let installer = services.installer
        let device = services.device
        return SummaryCoordinator(
            store: services.summaries,
            transcripts: services.transcripts,
            speakers: services.speakers,
            engine: services.language,
            arbiter: arbiter,
            models: { id in
                catalog.models.first { $0.id == id }.map { ($0, installer.folder(for: id)) }
            },
            profile: readerProfile,
            canRun: {
                guard gate.isOpen else { return false }
                return await device.condition().thermal != .critical
            },
        )
    }

    @Sendable
    nonisolated static func readerProfile() -> String? {
        let text = UserDefaults.standard.string(forKey: SummaryPreferences.profileKey) ?? ""
        return text.isEmpty ? nil : text
    }

    static func makeIndexer(services: Services, arbiter: ModelArbiter, gate: GenerationGate) -> KnowledgeIndexer {
        let device = services.device
        return KnowledgeIndexer(
            recordings: services.store,
            transcripts: services.transcripts,
            speakers: services.speakers,
            knowledge: services.knowledge,
            engine: services.embedder,
            arbiter: arbiter,
            canRun: {
                guard gate.isOpen else { return false }
                return await device.condition().thermal != .critical
            },
        )
    }

    static func makeAskQueue(
        services: Services,
        arbiter: ModelArbiter,
        gate: GenerationGate,
        indexer: KnowledgeIndexer,
        summaries: SummaryCoordinator,
    ) -> AskCoordinator {
        let catalog = services.catalog
        let installer = services.installer
        let device = services.device
        return AskCoordinator(
            conversations: services.conversations,
            knowledge: services.knowledge,
            recordings: services.store,
            transcripts: services.transcripts,
            speakers: services.speakers,
            summaries: services.summaries,
            language: services.language,
            embedder: services.embedder,
            indexer: indexer,
            arbiter: arbiter,
            models: { id in
                catalog.models.first { $0.id == id }.map { ($0, installer.folder(for: id)) }
            },
            profile: readerProfile,
            canRun: {
                guard gate.isOpen else { return false }
                return await device.condition().thermal != .critical
            },
            pauseOtherWork: { await summaries.suspend() },
            resumeOtherWork: { await summaries.resume() },
        )
    }

    static func summarizeIfWanted(
        _ id: RecordingID,
        queue: SummaryCoordinator,
        manager: ModelManager,
        store: any SummaryStore,
    ) async {
        let defaults = UserDefaults.standard
        guard
            defaults.bool(forKey: SummaryPreferences.autoKey),
            let model = await manager.model(for: .chat, language: nil)
        else { return }
        let saved = await (try? store.userTemplates()) ?? []
        let wanted = defaults.string(forKey: SummaryPreferences.defaultTemplateKey)
        let template = (BuiltInTemplates.all + saved).first { $0.id == wanted } ?? BuiltInTemplates.all[0]
        _ = try? await queue.enqueue(id, template: template, modelID: model.id, language: nil)
    }

    func connectSummaries(to recorder: RecordingController, device: any DeviceMonitor) {
        let queue = summaryQueue
        let askQueue = askQueue
        let indexer = knowledgeIndexer
        let gate = gate
        // Recording comes first. This never waits, so that the microphone starts on time.
        recorder.onActivityChanged = { isActive in
            gate.isRecording = isActive
            Task {
                if isActive {
                    await askQueue.stopAndRelease()
                    await indexer.suspend()
                    await queue.suspend()
                } else {
                    await queue.resume()
                    await indexer.run()
                }
            }
        }
        Task {
            // Picks up work paused by heat.
            for await _ in device.changes {
                await queue.resume()
                await indexer.run()
            }
        }
    }

    #if DEBUG
        static func startProbes(arguments: [String], services: Services, arbiter: ModelArbiter) {
            let catalog = services.catalog
            let installer = services.installer
            let engine = services.language
            let device = services.device
            let model = catalog.models.first { $0.runtime == .mlx }
            if arguments.contains("--llm-probe"), let model {
                Task {
                    await arbiter.acquire()
                    await LanguageProbe.run(
                        engine: engine, model: model, folder: installer.folder(for: model.id), device: device,
                    )
                    await arbiter.release()
                }
            }
            if arguments.contains("--summary-probe"), let model {
                // The phone must not lock during a run that lasts many minutes.
                UIApplication.shared.isIdleTimerDisabled = true
                Task {
                    await SummaryProbe.run(
                        engine: engine, arbiter: arbiter, model: model,
                        folder: installer.folder(for: model.id), device: device,
                    )
                }
            }
        }
    #endif
}
