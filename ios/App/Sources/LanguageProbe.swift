#if DEBUG
    import Domain
    import Foundation

    /// SP-1: can a language model summarize real meetings on this phone, and at what cost?
    /// Runs only with `--llm-probe` in debug builds, and writes its results to Documents.
    enum LanguageProbe {
        private struct Case {
            let label: String
            let system: String
            let prompt: String
        }

        static let english = """
        Ana: Good morning. Today we need to decide on the office move and the hiring plan.
        Bruno: I reviewed the numbers. We can afford the new office if we delay two hires by two months.
        Ana: Delaying hires worries me, because support is already stretched.
        Carla: Support tickets grew thirty percent this quarter, so I agree with Ana.
        Bruno: Then the alternative is a smaller space, but the landlord only offers two floors together.
        Ana: Let us keep the two floors, and delay hiring by one month instead of two.
        Carla: I can live with one month if we add a temporary contractor for support.
        Bruno: A contractor costs about eight thousand a month. That fits the budget.
        Ana: Decided. Bruno updates the budget by Friday, and Carla opens the contractor role today.
        Carla: I will also send the new support forecast to everyone next Monday.
        """

        static let portuguese = """
        Marina: Bom dia. Hoje precisamos decidir a data de lançamento do aplicativo.
        Pedro: A equipe de testes achou um erro no login em celulares antigos.
        Marina: Quantos usuários são afetados?
        Pedro: Cerca de três por cento, e eles não conseguem entrar de jeito nenhum.
        Lucas: Então não dá para lançar assim. Eu adiaria três dias.
        Marina: Concordo. Lançamos na quinta-feira, e não na segunda.
        Pedro: Eu corrijo o erro até terça, e o Lucas testa na quarta de manhã.
        Lucas: Combinado. Vou avisar o marketing hoje para mudar o anúncio.
        Marina: Perfeito. Decidido, então.
        """

        static let japanese = """
        佐藤：おはようございます。今日は新製品の価格を決めましょう。
        鈴木：競合は九千八百円です。こちらは一万円以下にすべきだと思います。
        田中：原価を考えると、最低でも八千五百円は必要です。
        佐藤：では九千五百円でいかがでしょうか。
        鈴木：賛成です。発売記念の割引も検討したいです。
        田中：割引は最初の一か月だけなら問題ありません。
        佐藤：決定します。価格は九千五百円、発売から一か月は一割引とします。
        鈴木：私が来週月曜日までに販売資料を更新します。
        田中：私は今週中に原価表を経理に共有します。
        """

        private static let cases = [
            Case(
                label: "en",
                system: "You summarize meetings accurately. Use only facts from the transcript. Never invent.",
                prompt: "Write a summary with: Key points, Decisions, Action items (owner and date).\n\n\(english)",
            ),
            Case(
                label: "pt-BR",
                system: """
                Você resume reuniões com precisão. Use só fatos da transcrição. Nunca invente. Responda em português.
                """,
                prompt: """
                Escreva um resumo com: Pontos principais, Decisões, Tarefas (responsável e data).

                \(portuguese)
                """,
            ),
            Case(
                label: "ja",
                system: "あなたは会議を正確に要約します。文字起こしの事実だけを使い、創作しないでください。日本語で答えてください。",
                prompt: "次の項目で要約してください：要点、決定事項、タスク（担当者と期限）。\n\n\(japanese)",
            ),
        ]

        static func run(
            engine: any LanguageModelEngine,
            model: ModelDescriptor,
            folder: URL?,
            device: any DeviceMonitor,
        ) async {
            var results: [LanguageProbeResult] = []
            let started = Date()
            var loadSeconds = 0.0
            var loadError: String?
            do {
                try await engine.prepare(model: model, folder: folder)
                loadSeconds = Date().timeIntervalSince(started)
            } catch {
                loadError = "\(error)"
            }
            for item in cases where loadError == nil {
                await results.append(run(item, engine: engine, loadSeconds: loadSeconds, device: device))
                write(results, status: "running")
            }
            if let loadError {
                results.append(LanguageProbeResult(
                    label: "load", promptCharacters: 0, loadSeconds: 0, firstChunkSeconds: 0, chunksPerSecond: 0,
                    chunks: 0, lowestAvailableMemoryMB: 0, thermalStart: 0, thermalEnd: 0, output: "",
                    error: loadError,
                ))
            }
            await engine.unload()
            write(results, status: "done")
        }

        private static func run(
            _ item: Case,
            engine: any LanguageModelEngine,
            loadSeconds: Double,
            device: any DeviceMonitor,
        ) async -> LanguageProbeResult {
            let thermalStart = await device.condition().thermal.rawValue
            var lowest = await device.condition().availableMemoryMB
            let start = Date()
            var first: Double?
            var chunks = 0
            var output = ""
            var failure: String?
            do {
                let request = LanguageRequest(system: item.system, prompt: item.prompt, maxTokens: 400)
                for try await chunk in engine.generate(request) {
                    if first == nil {
                        first = Date().timeIntervalSince(start)
                    }
                    chunks += 1
                    output += chunk
                    if chunks % 20 == 0 {
                        lowest = await min(lowest, device.condition().availableMemoryMB)
                    }
                }
            } catch {
                failure = "\(error)"
            }
            let total = Date().timeIntervalSince(start)
            let generating = max(total - (first ?? 0), 0.001)
            return await LanguageProbeResult(
                label: item.label,
                promptCharacters: item.prompt.count,
                loadSeconds: loadSeconds,
                firstChunkSeconds: first ?? 0,
                chunksPerSecond: Double(chunks) / generating,
                chunks: chunks,
                lowestAvailableMemoryMB: lowest,
                thermalStart: thermalStart,
                thermalEnd: device.condition().thermal.rawValue,
                output: output,
                error: failure,
            )
        }

        private static func write(_ results: [LanguageProbeResult], status: String) {
            guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            if let data = try? encoder.encode(results) {
                try? data.write(to: folder.appending(path: "llm-probe.json"), options: .atomic)
            }
            try? Data(status.utf8).write(to: folder.appending(path: "llm-probe.status"), options: .atomic)
        }
    }
#endif
