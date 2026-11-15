package com.meetlaud.domain

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.time.Instant
import java.util.Locale
import java.util.UUID

/**
 * The Kotlin Domain against the iOS one (D-084). Tools/parity/golden.json is what the Swift Domain returned for
 * Tools/parity/cases.json, and this must return exactly the same text. A failure means the apps would behave
 * differently for the same meeting. Mirrors Tools/parity/Runner.swift case for case.
 */
class ParityTest {
    private val parity = File(System.getProperty("parity.dir") ?: "../../Tools/parity")
    private val recording = RecordingID(UUID.fromString("11111111-1111-1111-1111-111111111111"))

    @Test
    fun theKotlinDomainMatchesTheSwiftOne() {
        Locale.setDefault(Locale.US)
        TextBreaks.breaker = ::icu
        val cases = Json.parseToJsonElement(File(parity, "cases.json").readText()).jsonArray
        val golden = Json.parseToJsonElement(File(parity, "golden.json").readText()).jsonArray
            .associate { it.jsonObject["id"]!!.jsonPrimitive.content to it.jsonObject["output"]!!.jsonPrimitive.content }
        // Pinned on both sides, so that a known difference that changes is a failure too.
        val known = Json.parseToJsonElement(File(parity, "known-differences.json").readText()).jsonObject["differences"]!!.jsonArray
            .associate { it.jsonObject["id"]!!.jsonPrimitive.content to (it.jsonObject["swift"]!!.jsonPrimitive.content to it.jsonObject["kotlin"]!!.jsonPrimitive.content) }
        val failures = mutableListOf<String>()
        for (element in cases) {
            val case = element.jsonObject
            val id = case["id"]!!.jsonPrimitive.content
            val expected = golden[id] ?: run { failures.add("$id: missing from golden.json, run Tools/parity/run"); continue }
            val actual = runCatching { run(case["fn"]!!.jsonPrimitive.content, case["args"]!!.jsonObject) }
                .getOrElse { "threw $it" }
            if (known[id] == (expected to actual)) continue
            if (actual != expected) failures.add("$id\n  swift:  ${expected.replace("\n", "⏎")}\n  kotlin: ${actual.replace("\n", "⏎")}")
        }
        if (failures.isNotEmpty()) fail("${failures.size} of ${cases.size} cases differ from iOS:\n" + failures.joinToString("\n"))
    }

    // MARK: - Reading arguments

    private fun JsonObject.str(key: String) = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: ""
    private fun JsonObject.optStr(key: String) = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
    private fun JsonObject.num(key: String) = (this[key] as? JsonPrimitive)?.doubleOrNull ?: 0.0
    private fun JsonObject.optNum(key: String) = (this[key] as? JsonPrimitive)?.doubleOrNull
    private fun JsonObject.int(key: String) = num(key).toInt()
    private fun JsonObject.bool(key: String) = (this[key] as? JsonPrimitive)?.booleanOrNull ?: false
    private fun JsonObject.optBool(key: String) = (this[key] as? JsonPrimitive)?.booleanOrNull
    private fun JsonObject.arr(key: String): List<JsonElement> = (this[key] as? JsonArray) ?: emptyList()
    private fun JsonObject.strings(key: String) = arr(key).mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }
    private fun uuid(text: String) = UUID.fromString(text)

    private fun segments(list: List<JsonElement>) = list.map {
        val o = it.jsonObject
        TranscriptSegment(uuid(o.str("id")), recording, o.num("start"), o.num("end"), o.str("text"), o.optStr("speaker"))
    }

    private fun floats(list: List<JsonElement>) = list.mapNotNull { (it as? JsonPrimitive)?.doubleOrNull?.toFloat() }

    private fun speakers(list: List<JsonElement>) = list.map {
        val o = it.jsonObject
        Speaker(uuid(o.str("id")), recording, o.int("number"), o.optStr("name"), embedding = floats(o.arr("embedding")), talkTime = o.num("talkTime"))
    }

    private fun turns(list: List<JsonElement>) = list.map {
        val o = it.jsonObject
        SpeakerTurn(o.str("speaker"), o.num("start"), o.num("end"), floats(o.arr("embedding")))
    }

    private fun excerpts(list: List<JsonElement>) = list.map {
        val o = it.jsonObject
        AskExcerpt(RecordingID(uuid(o.str("recording"))), o.str("title"), o.num("time"), o.optNum("end"), o.str("text"))
    }

    private fun items(list: List<JsonElement>) = list.map {
        val o = it.jsonObject
        SummaryItem(uuid(o.str("id")), o.str("text"), o.optNum("sourceTime"), o.optStr("owner"), o.optStr("due"), o.bool("isDone"), o.bool("needsReview"))
    }

    private fun kind(text: String) = if (text == "tasks") SectionKind.TASKS else SectionKind.BULLETS

    private fun summary(o: JsonObject) = Summary(
        uuid("22222222-2222-2222-2222-222222222222"), recording, o.str("template"), "model", o.optStr("language"),
        o.arr("sections").map { val s = it.jsonObject; SummarySection(s.str("title"), kind(s.str("kind")), items(s.arr("items"))) },
        true, Instant.EPOCH,
    )

    private fun template(id: String) = BuiltInTemplates.all.first { it.id == id }

    // MARK: - Writing outputs, the same way Runner.swift does

    private fun f(value: Double?): String = value?.let { String.format(Locale.ROOT, "%.4f", it) } ?: "<nil>"
    private fun f(value: Float): String = f(value.toDouble())
    private fun s(value: String?) = value ?: "<nil>"

    private fun show(request: LanguageRequest) = "${request.system}\n---\n${request.prompt}\n---${request.maxTokens} ${f(request.temperature.toDouble())}"

    private fun show(item: SummaryItem) =
        listOf(item.text, f(item.sourceTime), s(item.owner), s(item.due), "${item.isDone}", "${item.needsReview}").joinToString(" | ")

    private fun show(citation: Citation) =
        listOf("${citation.number}", citation.recordingID.rawValue.uuidString, citation.recordingTitle, f(citation.time), citation.excerpt).joinToString(" | ")

    private fun show(node: MindMapNode, depth: Int = 0): String =
        (listOf("  ".repeat(depth) + "${node.id} | ${node.title} | ${f(node.time)}") + node.children.map { show(it, depth + 1) }).joinToString("\n")

    private fun label(label: FitLabel) = when (label) {
        FitLabel.UNSUPPORTED -> "unsupported"
        FitLabel.NOT_RECOMMENDED -> "notRecommended"
        FitLabel.MAY_SLOW -> "maySlow"
        FitLabel.GOOD -> "good"
        FitLabel.BEST -> "best"
    }

    private fun reason(reason: FitReason) = when (reason) {
        FitReason.BestForDevice -> "bestForDevice"
        FitReason.WorksWell -> "worksWell"
        FitReason.BelowTargetSpeed -> "belowTargetSpeed"
        FitReason.NotEnoughMemory -> "notEnoughMemory"
        FitReason.UnstableHere -> "unstableHere"
        is FitReason.LanguageNotCovered -> "languageNotCovered(${reason.language})"
    }

    private fun speed(speed: SpeedEvidence) = when (speed) {
        is SpeedEvidence.Estimated -> "estimated(${f(speed.low)}, ${f(speed.high)})"
        is SpeedEvidence.Measured -> "measured(${f(speed.value)})"
        SpeedEvidence.Unknown -> "unknown"
    }

    private fun rightNow(value: RightNow): String {
        fun reason(reason: RightNow.Reason) = when (reason) {
            RightNow.Reason.WARM -> "warm"
            RightNow.Reason.HOT -> "hot"
            RightNow.Reason.LOW_POWER -> "lowPower"
            RightNow.Reason.LOW_BATTERY -> "lowBattery"
            RightNow.Reason.LOW_MEMORY -> "lowMemory"
        }
        return when (value) {
            RightNow.Great -> "great"
            is RightNow.Good -> "good(${reason(value.reason)})"
            is RightNow.Limited -> "limited(${reason(value.reason)})"
            RightNow.Paused -> "paused"
        }
    }

    private fun condition(o: JsonObject) = DeviceCondition(
        when (o.str("thermal")) { "fair" -> ThermalLevel.FAIR; "serious" -> ThermalLevel.SERIOUS; "critical" -> ThermalLevel.CRITICAL; else -> ThermalLevel.NOMINAL },
        o.bool("isLowPower"), o.bool("isCharging"), o.num("batteryLevel"), o.int("availableMemoryMB"), o.num("freeBytes").toLong(),
    )

    private fun stats(list: List<JsonElement>) = list.map {
        val o = it.jsonObject
        ModelRunStat(
            o.str("modelID"), o.num("audioDuration"), o.num("wallTime"),
            if (o.str("outcome") == "killed") ModelRunStat.Outcome.KILLED else ModelRunStat.Outcome.COMPLETED,
            Instant.ofEpochMilli((o.num("date") * 1000).toLong()),
        )
    }

    private val catalogJson = Json { ignoreUnknownKeys = true }

    // MARK: - Running

    private fun run(fn: String, a: JsonObject): String = when (fn) {
        "markRepeats" -> TranscriptCleanup.markRepeats(a.str("text"))
        "hasWords" -> "${TranscriptCleanup.hasWords(a.str("text"))}"
        "vocabulary" -> {
            val entries = a.arr("entries").map {
                val o = it.jsonObject
                VocabularyEntry(heard = o.str("heard"), written = o.str("written"), folderID = o.optStr("folder")?.let { f -> FolderID(uuid(f)) })
            }
            val applied = entries.applying(a.optStr("folder")?.let { FolderID(uuid(it)) })
            VocabularyCorrector.apply(applied, a.str("text")) + "\n" + TranscriptionHints.from(applied).joinToString("|")
        }
        "polish" -> TranscriptPolish.polish(a.str("text"))
        "languageWrong" -> "${LanguageCheck.isWrong(a.str("text"), a.str("language"))}"
        "queryTerms" -> QueryTerms.terms(a.str("text")).joinToString("|")
        "answerParse" -> {
            val result = AnswerParser.parse(a.str("text"), excerpts(a.arr("excerpts")))
            (listOf(result.body, "${result.hasBasis}") + result.citations.map { show(it) }).joinToString("\n")
        }
        "answerVisible" -> AnswerParser.visible(a.str("text"))
        "copyingStart" -> AnswerParser.copyingStart(a.str("text"))?.toString() ?: "<nil>"
        "claim" -> CitationLocator.claim(a.int("number"), a.str("body"))
        "phrase" -> s(CitationLocator.phrase(a.str("claim"), segments(a.arr("segments")))?.id?.uuidString)
        "memory" -> s(MemoryCommand.text(a.str("text")))
        "askPrompt" -> {
            val history = a.arr("history").mapIndexed { index, it ->
                val o = it.jsonObject
                ChatMessage(
                    conversationID = uuid("33333333-3333-3333-3333-333333333333"),
                    role = if (o.str("role") == "user") ChatRole.USER else ChatRole.ASSISTANT,
                    body = o.str("body"),
                    state = AnswerState.from(o.str("state")) ?: AnswerState.COMPLETE,
                    createdAt = Instant.ofEpochSecond(index.toLong()),
                )
            }
            val memories = a.strings("memories").map { MemoryItem(text = it, createdAt = Instant.EPOCH) }
            show(AskPrompts.answer(a.str("question"), excerpts(a.arr("excerpts")), history, memories, a.optStr("profile"), a.optStr("skill")))
        }
        "notesPrompt" -> show(SummaryPrompts.notes(a.strings("lines"), a.optStr("language")))
        "sectionPrompt" -> {
            val t = template(a.str("template"))
            show(SummaryPrompts.section(t.sections[a.int("section")], t, a.strings("notes"), a.optStr("language"), a.optStr("spoken"), a.optStr("profile"), a.optNum("limit")?.toInt()))
        }
        "translationPrompt" -> show(SummaryPrompts.translation(a.strings("lines"), a.str("language"), a.strings("names")))
        "draftPrompt" -> show(SummaryPrompts.templateDraft(a.str("description"), a.optStr("language")))
        "summaryItems" -> SummaryParser.items(a.str("text"), kind(a.str("kind"))).joinToString("\n") { show(it) }
        "summaryNotes" -> SummaryParser.notes(a.str("text")).joinToString("\n")
        "balanced" -> SummaryParser.balanced(a.arr("parts").map { items(it.jsonArray) }, kind(a.str("kind"))).joinToString("\n") { show(it) }
        "summaryLine" -> items(a.arr("items")).joinToString("\n") { SummaryParser.line(it, kind(a.str("kind"))) }
        "validate" -> items(a.arr("items")).joinToString("\n") {
            show(SummaryValidator.validate(it, segments(a.arr("segments")), speakers(a.arr("speakers")), a.optBool("sameLanguage") ?: true))
        }
        "echoedExample" -> items(a.arr("items")).joinToString("\n") { "${SummaryValidator.isEchoedExample(it, segments(a.arr("segments")))}" }
        "speakerTokens" -> {
            val encoded = SpeakerTokens.encode(a.str("text"), speakers(a.arr("speakers")))
            encoded + "\n" + SpeakerTokens.decode(encoded, speakers(a.arr("renamed")))
        }
        "parseDraft" -> runCatching { TemplateCodec.parseDraft(a.str("text")) }.map { t ->
            (listOf(t.name, t.instructions) + t.sections.map { "${it.title} | ${it.kind.raw}" }).joinToString("\n")
        }.getOrDefault("invalid")
        "templateDecode" -> runCatching { TemplateCodec.decode(a.str("text").encodeToByteArray()) }.map { t ->
            (listOf(t.name, t.category.raw, t.instructions) + t.sections.map { "${it.title} | ${it.kind.raw}" }).joinToString("\n")
        }.getOrDefault("invalid")
        "skillDecode" -> runCatching { SkillCodec.decode(a.str("text").encodeToByteArray()) }.map { skill ->
            listOf(skill.name, skill.summary, skill.instructions, "${skill.isBuiltIn}").joinToString("\n")
        }.getOrDefault("invalid")
        "exportTranscript" -> TranscriptExporter.text(
            a.str("title"), segments(a.arr("segments")), speakers(a.arr("speakers")),
            TranscriptFormat.entries.first { it.fileExtension == a.str("format") },
            ExportOptions(a.optBool("speakers_on") ?: true, a.optBool("times_on") ?: true),
        )
        "exportSummary" -> SummaryExporter.markdown(a.str("title"), summary(a["summary"]!!.jsonObject), speakers(a.arr("speakers")))
        "fileName" -> ExportFileName.safe(a.str("title"), a.str("ext"))
        "chunks" -> {
            val people = speakers(a.arr("speakers"))
            val all = segments(a.arr("segments"))
            (listOf(KnowledgeChunker.sourceHash(all, people)) +
                KnowledgeChunker.chunks(all, people, a.optStr("language")).map { "${f(it.start)} | ${f(it.end)} | ${it.text}" }).joinToString("\n")
        }
        "formatterLines" -> TranscriptFormatter.chunks(TranscriptFormatter.lines(segments(a.arr("segments")), speakers(a.arr("speakers"))), a.int("limit"))
            .joinToString("\n===\n") { it.joinToString("\n") }
        "tokens" -> "${TokenEstimator.tokens(a.str("text"))}"
        "rankFusion" -> RankFusion.merge(a.arr("lists").map { list -> list.jsonArray.map { uuid(it.jsonPrimitive.content) } }, a.int("limit"))
            .joinToString("\n") { it.uuidString }
        "speakerStats" -> SpeakerStats.compute(speakers(a.arr("speakers")), segments(a.arr("segments"))).joinToString("\n") {
            "${it.speakerID.uuidString} | ${f(it.talkTime)} | ${f(it.share)} | ${it.turns} | ${f(it.longestTurn)}"
        }
        "alignment" -> {
            val all = segments(a.arr("segments"))
            val result = SpeakerAlignment.assign(all, turns(a.arr("turns")))
            all.joinToString("\n") { "${it.id.uuidString} | ${s(result[it.id])}" }
        }
        "passingSounds" -> SpeakerPipeline.withoutPassingSounds(turns(a.arr("turns"))).joinToString("\n") { "${it.speaker} | ${f(it.start)} | ${f(it.end)}" }
        "centroid" -> {
            val all = turns(a.arr("turns"))
            SpeakerPipeline.centroid(all).joinToString(" ") { f(it) } + "\n" +
                (VoiceSeparation.closestPair(all)?.let { f(it.toDouble()) } ?: "<nil>") + "\n" + "${VoiceSeparation.areDistinct(all)}"
        }
        "voiceMatch" -> {
            val embedding = a.strings("embedding").map { it.toFloat() }
            val prints = a.arr("prints").map {
                val o = it.jsonObject
                VoicePrint(uuid(o.str("person")), "m", o.strings("embedding").map { v -> v.toFloat() }, o.num("talkTime"))
            }
            val match = when (val result = VoiceMatcher.match(embedding, prints)) {
                is VoiceMatch.Suggested -> "suggested | ${result.personID.uuidString} | ${f(result.score.toDouble())}"
                is VoiceMatch.Uncertain -> "uncertain | ${result.personID.uuidString} | ${f(result.score.toDouble())}"
                VoiceMatch.Unknown -> "unknown"
            }
            val blend = if (prints.size >= 2) {
                VoiceMatcher.blend(prints[0].embedding, prints[0].talkTime, prints[1].embedding, prints[1].talkTime).joinToString(" ") { f(it) }
            } else ""
            match + "\n" + blend
        }
        "recommend" -> {
            val catalog = catalogJson.decodeFromJsonElement(kotlinx.serialization.builtins.ListSerializer(ModelDescriptor.serializer()), a["catalog"]!!)
            val device = a["device"]!!.jsonObject
            val context = RecommendationContext(
                DeviceProfile("d", device.str("identifier"), device.int("memory"), probeScore = device.num("probe")),
                a.strings("languages"),
                Priority.from(a.str("priority")) ?: Priority.BALANCED,
                stats(a.arr("history")),
            )
            val engine = RecommendationEngine()
            val lines = mutableListOf<String>()
            for (role in ModelRole.entries) {
                for (fit in engine.recommend(role, catalog, context)) {
                    lines.add("${role.raw} | ${fit.model.id} | ${label(fit.label)} | ${reason(fit.reason)} | ${speed(fit.speed)}")
                }
                lines.add("${role.raw} auto | ${s(engine.automaticModel(role, catalog, a.strings("languages").firstOrNull(), context)?.id)}")
            }
            val suggestions = AdvisorRules().suggestions(
                catalog, a.strings("installed").toSet(), context, condition(a["condition"]!!.jsonObject),
                Instant.ofEpochSecond(a.num("now").toLong()),
            )
            (lines + suggestions.map { it.id }).joinToString("\n")
        }
        "rightNow" -> rightNow(RightNow.evaluate(condition(a["condition"]!!.jsonObject), a.int("required")))
        "plan" -> {
            val evidence = when (a.str("speed")) {
                "measured" -> SpeedEvidence.Measured(a.num("value"))
                "estimated" -> SpeedEvidence.Estimated(a.num("low"), a.num("high"))
                else -> SpeedEvidence.Unknown
            }
            val plan = TranscribePlan(a.num("duration"), evidence, RightNow.evaluate(condition(a["condition"]!!.jsonObject)), a.bool("isCharging"))
            "${plan.minutes?.let { "${it.first}...${it.last}" } ?: "<nil>"} | ${plan.deservesNote} | ${plan.canWaitForCharger}"
        }
        "summaryParts" -> SummaryParts.split(a.strings("notes"), a.num("duration")).joinToString("\n===\n") { it.joinToString("\n") }
        "isQuestion" -> "${SectionGuide.isQuestion(a.str("text"))}"
        "languageName" -> SummaryLanguage.name(a.str("code"))
        "mindMap" -> show(MindMapNode.tree(a.str("title"), summary(a["summary"]!!.jsonObject)))
        "keptNames" -> SummaryCoordinator.keptNames(speakers(a.arr("speakers")), a.optStr("language")).joinToString("|")
        "stableHash" -> StableHash.hex(a.str("text"))
        "transcriptionHints" -> TranscriptionHints.from(a.strings("written").map { VocabularyEntry(heard = "x", written = it) }).joinToString("|")
        "sort" -> {
            val recordings = a.strings("titles").mapIndexed { index, title ->
                Recording(title = title, createdAt = Instant.ofEpochSecond(index.toLong()), duration = (index * 7 % 5).toDouble())
            }
            RecordingSort.entries.joinToString("\n") { sort -> sort.raw + ": " + sort.sorted(recordings).joinToString(" / ") { it.title } }
        }
        else -> "unknown function $fn"
    }

    /** ICU4J, which is what java.text.BreakIterator is on Android. */
    private fun icu(text: String, unit: TextBreaks.Unit, locale: Locale): List<String> {
        val iterator = if (unit == TextBreaks.Unit.WORD) com.ibm.icu.text.BreakIterator.getWordInstance(locale)
        else com.ibm.icu.text.BreakIterator.getSentenceInstance(locale)
        iterator.setText(text)
        val result = mutableListOf<String>()
        var start = iterator.first()
        var end = iterator.next()
        while (end != com.ibm.icu.text.BreakIterator.DONE) {
            result.add(text.substring(start, end))
            start = end
            end = iterator.next()
        }
        return result
    }
}
