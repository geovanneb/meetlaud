package com.meetlaud.app

import com.meetlaud.app.infra.persistence.DatabaseStore
import com.meetlaud.domain.AskScope
import com.meetlaud.domain.ChatMessage
import com.meetlaud.domain.ChatRole
import com.meetlaud.domain.Citation
import com.meetlaud.domain.Conversation
import com.meetlaud.domain.Folder
import com.meetlaud.domain.Marker
import com.meetlaud.domain.MarkerKind
import com.meetlaud.domain.Person
import com.meetlaud.domain.Recording
import com.meetlaud.domain.SectionKind
import com.meetlaud.domain.Speaker
import com.meetlaud.domain.Summary
import com.meetlaud.domain.SummaryItem
import com.meetlaud.domain.SummarySection
import com.meetlaud.domain.Transcript
import com.meetlaud.domain.TranscriptSegment
import com.meetlaud.domain.TranscriptionJob
import com.meetlaud.domain.uuidString
import java.time.Instant

/**
 * Fictional meetings for screenshots and demos, the same as ios/App/Sources/ShowcaseSeed.swift, so both apps can be
 * compared screen by screen. Every person, company, and number here is invented. Debug builds only: launch with
 * `--ez showcase true`.
 *
 * English is the library iOS seeds. The other languages exist for the store screenshots (docs/store), so a person
 * reading the Japanese listing sees a Japanese meeting, not an English one under Japanese menus.
 */
object Showcase {
    /** What the scripted model answers, in order. */
    val answers = listOf(
        "Two decisions: the print ads are dropped and their budget moves to video [7], and the launch stays on March 3 [10].",
    )

    private class Line(val time: Double, val speaker: Int, val text: String)

    /** One language's library. Times, speakers, and structure are the same in every language. */
    private class Library(
        val language: String,
        val folders: List<String>,
        val people: List<String>,
        /** The meeting everything opens: its title, then the five others, newest first. */
        val titles: List<String>,
        val lines: List<String>,
        val note: String,
        val sections: List<String>,
        val keyPoints: List<String>,
        val decisions: List<String>,
        val tasks: List<String>,
        val dues: List<String>,
        val question: String,
        val answer: String,
    )

    private val times = listOf(0.0, 9.0, 21.0, 34.0, 41.0, 55.0, 66.0, 78.0, 87.0, 98.0)
    private val speakers = listOf(1, 2, 3, 1, 2, 3, 1, 2, 3, 1)

    private val english = Library(
        language = "en",
        folders = listOf("Marketing", "Clients"),
        people = listOf("Ana Ribeiro", "Kenji Sato", "Sofía Morales"),
        titles = listOf(
            "Spring campaign kickoff", "Interview with Harbor Bikes", "Weekly design sync", "Budget review",
            "1:1 with Kenji", "Partner call: Bluefin Studio",
        ),
        lines = listOf(
            "Thanks for joining. Let's lock the plan for the spring campaign today.",
            "I shared the draft. The main idea is short videos first, then email.",
            "Customers asked for real stories, so I'd lead with two customer videos.",
            "Agreed. What does that do to the budget?",
            "Video takes about forty percent. We can drop the print ads to cover it.",
            "Print brought almost no sign-ups last year, so I'm fine with that.",
            "Then it's decided: no print, and the budget moves to video.",
            "I can have the first script ready by Friday.",
            "I'll ask Harbor Bikes if they want to be the first story.",
            "Great. Launch date stays March 3. Let's review progress next Tuesday.",
        ),
        note = "Budget agreed",
        sections = listOf("Key points", "Decisions", "Action items"),
        keyPoints = listOf(
            "The campaign leads with short customer videos, then email.",
            "Customers asked for real stories in the last survey.",
            "Print ads brought almost no sign-ups last year.",
        ),
        decisions = listOf("No print ads. Their budget moves to video.", "Launch stays on March 3."),
        tasks = listOf("First video script", "Invite Harbor Bikes as the first story", "Progress review"),
        dues = listOf("Friday", "Tuesday"),
        question = "What decisions were made?",
        answer = "Two decisions: the print ads are dropped and their budget moves to video [1], and the launch stays on March 3 [2].",
    )

    private val japanese = Library(
        language = "ja",
        folders = listOf("マーケティング", "取引先"),
        people = listOf("佐藤 健二", "田中 美咲", "山本 彩"),
        titles = listOf(
            "春キャンペーン キックオフ", "ハーバーバイク様 ヒアリング", "週次デザイン定例", "予算レビュー",
            "健二さんと1on1", "ブルーフィン・スタジオ様 打ち合わせ",
        ),
        lines = listOf(
            "お集まりいただきありがとうございます。今日は春キャンペーンの計画を固めましょう。",
            "ドラフトを共有しました。まず短い動画、そのあとにメールという流れです。",
            "お客様から実際の事例を求める声が多いので、お客様の動画2本から始めたいです。",
            "賛成です。予算への影響はどうなりますか？",
            "動画で約4割を使います。紙の広告をやめれば賄えます。",
            "紙の広告は昨年ほとんど登録につながらなかったので、それで問題ありません。",
            "では決定です。紙の広告はやめて、予算は動画に回します。",
            "最初の台本は金曜日までに用意できます。",
            "ハーバーバイク様に最初の事例をお願いできるか聞いてみます。",
            "いいですね。公開日は3月3日のままで、来週火曜日に進捗を確認しましょう。",
        ),
        note = "予算合意",
        sections = listOf("要点", "決定事項", "アクションアイテム"),
        keyPoints = listOf(
            "キャンペーンはお客様の短い動画から始め、そのあとメールを送る。",
            "直近のアンケートで、お客様は実際の事例を求めていた。",
            "紙の広告は昨年ほとんど登録につながらなかった。",
        ),
        decisions = listOf("紙の広告はやめ、その予算を動画に回す。", "公開日は3月3日のまま。"),
        tasks = listOf("最初の動画の台本", "ハーバーバイク様に最初の事例を依頼", "進捗確認"),
        dues = listOf("金曜日", "火曜日"),
        question = "どんな決定がありましたか？",
        answer = "決定は2つです。紙の広告をやめて予算を動画に回すこと [1]、そして公開日を3月3日のままにすることです [2]。",
    )

    private val portuguese = Library(
        language = "pt",
        folders = listOf("Marketing", "Clientes"),
        people = listOf("Ana Ribeiro", "Lucas Almeida", "Beatriz Costa"),
        titles = listOf(
            "Kickoff da campanha de primavera", "Entrevista com a Harbor Bikes", "Alinhamento semanal de design",
            "Revisão do orçamento", "1:1 com o Lucas", "Call com parceiro: Bluefin Studio",
        ),
        lines = listOf(
            "Obrigada por virem. Vamos fechar hoje o plano da campanha de primavera.",
            "Compartilhei o rascunho. A ideia é começar com vídeos curtos e depois e-mail.",
            "Os clientes pediram histórias reais, então eu abriria com dois vídeos de clientes.",
            "Concordo. Como isso afeta o orçamento?",
            "O vídeo leva uns quarenta por cento. Dá para cortar os anúncios impressos para cobrir.",
            "O impresso quase não trouxe cadastros no ano passado, então por mim tudo bem.",
            "Então está decidido: nada de impresso, e a verba vai para vídeo.",
            "Consigo entregar o primeiro roteiro até sexta.",
            "Vou perguntar à Harbor Bikes se querem ser a primeira história.",
            "Ótimo. O lançamento continua em 3 de março. Revisamos o andamento na terça.",
        ),
        note = "Orçamento fechado",
        sections = listOf("Pontos principais", "Decisões", "Próximos passos"),
        keyPoints = listOf(
            "A campanha começa com vídeos curtos de clientes, depois e-mail.",
            "Os clientes pediram histórias reais na última pesquisa.",
            "Os anúncios impressos quase não trouxeram cadastros no ano passado.",
        ),
        decisions = listOf("Sem anúncios impressos. A verba vai para vídeo.", "O lançamento continua em 3 de março."),
        tasks = listOf("Roteiro do primeiro vídeo", "Convidar a Harbor Bikes para a primeira história", "Revisão do andamento"),
        dues = listOf("Sexta", "Terça"),
        question = "Quais decisões foram tomadas?",
        answer = "Duas decisões: os anúncios impressos saem e a verba vai para vídeo [1], e o lançamento continua em 3 de março [2].",
    )

    private val spanish = Library(
        language = "es",
        folders = listOf("Marketing", "Clientes"),
        people = listOf("Sofía Morales", "Diego Herrera", "Lucía Navarro"),
        titles = listOf(
            "Arranque de la campaña de primavera", "Entrevista con Harbor Bikes", "Reunión semanal de diseño",
            "Revisión del presupuesto", "1:1 con Diego", "Llamada con socio: Bluefin Studio",
        ),
        lines = listOf(
            "Gracias por venir. Hoy cerramos el plan de la campaña de primavera.",
            "Compartí el borrador. La idea es empezar con videos cortos y luego correo.",
            "Los clientes pidieron historias reales, así que abriría con dos videos de clientes.",
            "De acuerdo. ¿Cómo afecta eso al presupuesto?",
            "El video se lleva un cuarenta por ciento. Podemos quitar los anuncios impresos para cubrirlo.",
            "Lo impreso casi no trajo registros el año pasado, así que me parece bien.",
            "Entonces está decidido: nada de impresos, y el presupuesto pasa a video.",
            "Puedo tener el primer guion listo para el viernes.",
            "Le preguntaré a Harbor Bikes si quieren ser la primera historia.",
            "Perfecto. El lanzamiento sigue el 3 de marzo. Revisamos el avance el martes.",
        ),
        note = "Presupuesto acordado",
        sections = listOf("Puntos clave", "Decisiones", "Tareas"),
        keyPoints = listOf(
            "La campaña empieza con videos cortos de clientes y luego correo.",
            "Los clientes pidieron historias reales en la última encuesta.",
            "Los anuncios impresos casi no trajeron registros el año pasado.",
        ),
        decisions = listOf("Sin anuncios impresos. Su presupuesto pasa a video.", "El lanzamiento sigue el 3 de marzo."),
        tasks = listOf("Guion del primer video", "Invitar a Harbor Bikes como primera historia", "Revisión del avance"),
        dues = listOf("Viernes", "Martes"),
        question = "¿Qué decisiones se tomaron?",
        answer = "Dos decisiones: se quitan los anuncios impresos y su presupuesto pasa a video [1], y el lanzamiento sigue el 3 de marzo [2].",
    )

    private fun library(language: String?): Library =
        listOf(japanese, portuguese, spanish).firstOrNull { it.language == language } ?: english

    /** @param language The app's language, such as "ja". Anything without a library of its own gets English. */
    suspend fun seed(store: DatabaseStore, language: String? = null) {
        if (store.observeRecordingsOnce().isNotEmpty()) return
        val text = library(language)
        val lines = text.lines.mapIndexed { index, line -> Line(times[index], speakers[index], line) }
        val now = Instant.now()
        val marketing = Folder(name = text.folders[0], createdAt = now)
        val clients = Folder(name = text.folders[1], createdAt = now)
        store.insert(marketing)
        store.insert(clients)

        val people = text.people
        val launch = Recording(
            title = text.titles[0], createdAt = now.minusSeconds(1800), duration = 2880.0,
            folderID = marketing.id, attendees = people,
        )
        store.insert(launch)
        listOf(
            Recording(title = text.titles[1], createdAt = now.minusSeconds(26000), duration = 1500.0, folderID = clients.id),
            Recording(title = text.titles[2], createdAt = now.minusSeconds(90000), duration = 1920.0, folderID = marketing.id),
            Recording(title = text.titles[3], createdAt = now.minusSeconds(176_000), duration = 3300.0),
            Recording(title = text.titles[4], createdAt = now.minusSeconds(260_000), duration = 1080.0),
            Recording(title = text.titles[5], createdAt = now.minusSeconds(350_000), duration = 2460.0, folderID = clients.id),
        ).forEach { store.insert(it) }
        store.insert(Marker(recordingID = launch.id, time = 312.0, kind = MarkerKind.NOTE, text = text.note))
        store.insert(Marker(recordingID = launch.id, time = 1260.0, kind = MarkerKind.FLAG))

        val found = people.mapIndexed { index, name ->
            Speaker(recordingID = launch.id, number = index + 1, name = name, embedding = listOf(index.toFloat(), 1f), talkTime = listOf(1140.0, 960.0, 780.0)[index])
        }
        people.forEach { store.insert(Person(name = it, createdAt = now)) }
        val segments = lines.mapIndexed { index, line ->
            TranscriptSegment(
                recordingID = launch.id, start = line.time,
                end = if (index + 1 < lines.size) lines[index + 1].time else line.time + 10,
                text = line.text, speaker = found[line.speaker - 1].id.uuidString,
            )
        }
        store.append(segments, TranscriptionJob(launch.id, "fake-small", text.language))
        store.deleteJob(launch.id)
        store.save(Transcript(launch.id, "fake-small", text.language, isComplete = true))
        // Assignments go by the speaker column already on each phrase, as on iOS.
        store.saveSpeakers(found, segments.associate { segment -> segment.id to found.first { it.id.uuidString == segment.speaker }.id }, launch.id)
        store.save(
            Summary(
                recordingID = launch.id, templateName = "Summary", modelID = "fake-chat", language = text.language, isComplete = true, createdAt = now,
                sections = listOf(
                    SummarySection(text.sections[0], SectionKind.BULLETS, listOf(
                        SummaryItem(text = text.keyPoints[0], sourceTime = 9.0),
                        SummaryItem(text = text.keyPoints[1], sourceTime = 21.0),
                        SummaryItem(text = text.keyPoints[2], sourceTime = 55.0),
                    )),
                    SummarySection(text.sections[1], SectionKind.BULLETS, listOf(
                        SummaryItem(text = text.decisions[0], sourceTime = 66.0),
                        SummaryItem(text = text.decisions[1], sourceTime = 98.0),
                    )),
                    SummarySection(text.sections[2], SectionKind.TASKS, listOf(
                        SummaryItem(text = text.tasks[0], sourceTime = 78.0, owner = people[1], due = text.dues[0]),
                        SummaryItem(text = text.tasks[1], sourceTime = 87.0, owner = people[2]),
                        SummaryItem(text = text.tasks[2], sourceTime = 98.0, owner = people[0], due = text.dues[1]),
                    )),
                ),
            ),
        )

        // A finished chat about the kickoff, so Ask can be shown without running a model.
        val chat = Conversation(title = text.question, scope = AskScope.Recording(launch.id), createdAt = now)
        store.save(chat)
        store.save(ChatMessage(conversationID = chat.id, role = ChatRole.USER, body = text.question, createdAt = now))
        store.save(
            ChatMessage(
                conversationID = chat.id, role = ChatRole.ASSISTANT, body = text.answer, createdAt = now.plusSeconds(4),
                citations = listOf(
                    Citation(1, launch.id, launch.title, lines[6].time, "${people[0]}: ${lines[6].text}"),
                    Citation(2, launch.id, launch.title, lines[9].time, "${people[0]}: ${lines[9].text}"),
                ),
            ),
        )
    }
}
