package com.meetlaud.domain

import java.io.File
import java.time.Instant
import java.util.UUID

/** A UUID as Swift's uuidString writes it: uppercase. Stored strings use this form on both platforms. */
val UUID.uuidString: String get() = toString().uppercase()

/** Someone who spoke in one recording. `name` stays null until a person is known, and the UI shows "Speaker N". */
data class Speaker(
    val id: UUID = UUID.randomUUID(),
    val recordingID: RecordingID,
    val number: Int,
    val name: String? = null,
    val personID: UUID? = null,
    /** The name came from a voice print and nobody confirmed it yet. */
    val isSuggested: Boolean = false,
    val embedding: List<Float> = emptyList(),
    val talkTime: TimeInterval = 0.0,
)

data class Person(val id: UUID = UUID.randomUUID(), val name: String, val createdAt: Instant)

/**
 * A vector that describes a voice. It is not audio, and audio cannot be rebuilt from it. Vectors from different
 * models cannot be compared, so each one records its model.
 */
data class VoicePrint(val personID: UUID, val modelID: String, val embedding: List<Float>, val talkTime: TimeInterval)

/** One stretch of one voice, from the diarization model. */
data class SpeakerTurn(val speaker: String, val start: TimeInterval, val end: TimeInterval, val embedding: List<Float>)

/** How many voices a recording holds, when the person knows it. */
sealed interface SpeakerCount {
    /** The model decides. */
    data object Automatic : SpeakerCount
    /** The person said how many people spoke. */
    data class Exactly(val count: Int) : SpeakerCount

    companion object {
        /** The counts a person can pick. */
        val choices = (2..10).toList()
    }
}

interface DiarizationEngine : ModelRunner {
    /** Reads the file by streaming, so that memory stays flat however long the meeting is. */
    suspend fun diarize(file: File, speakers: SpeakerCount = SpeakerCount.Automatic): List<SpeakerTurn>
}

interface SpeakerStore {
    suspend fun speakers(id: RecordingID): List<Speaker>
    /** Replaces the recording's speakers and assigns each phrase in one transaction. */
    suspend fun saveSpeakers(speakers: List<Speaker>, assignments: Map<UUID, UUID>, id: RecordingID)
    suspend fun update(speaker: Speaker)
    suspend fun setSpeaker(speakerID: UUID, segmentID: UUID)
    /** Moves every phrase from one speaker to another, and removes the first. */
    suspend fun merge(source: UUID, target: UUID)

    suspend fun people(): List<Person>
    suspend fun insert(person: Person)
    suspend fun update(person: Person)
    /** Removes the person and their voice prints. Names in old transcripts stay. */
    suspend fun deletePerson(id: UUID)
    /** One transaction. Their meetings follow, and the target's voice print wins where both have one. */
    suspend fun mergePerson(source: UUID, target: Person)
    suspend fun voicePrints(modelID: String): List<VoicePrint>
    suspend fun save(print: VoicePrint)
    suspend fun recordings(person: UUID): List<RecordingID>
}

/** Turns raw turns into the recording's speakers, and recognizes people who were saved before. */
class SpeakerPipeline(
    private val store: SpeakerStore,
    private val transcripts: TranscriptStore,
    private val engine: DiarizationEngine,
    private val model: suspend () -> Pair<ModelDescriptor, File?>?,
) {
    /** Whether there is anything to run. With no model, transcripts simply have no speakers. */
    suspend fun isAvailable(): Boolean = model() != null

    suspend fun run(id: RecordingID, file: File, count: SpeakerCount = SpeakerCount.Automatic) {
        val (descriptor, folder) = model() ?: return
        engine.prepare(descriptor, folder)
        val raw = try {
            engine.diarize(file, count)
        } catch (error: Throwable) {
            engine.unload()
            throw error
        }
        engine.unload()
        // A count the person chose is kept whole. Otherwise a "voice" heard for a moment is a cough or a click.
        val turns = if (count == SpeakerCount.Automatic) withoutPassingSounds(raw) else raw

        val segments = transcripts.segments(id)
        val assignment = SpeakerAlignment.assign(segments, turns)
        val speakers = speakers(turns, id).toMutableList()
        val prints = store.voicePrints(descriptor.id)
        recognize(speakers, prints)

        val byLabel = speakers.associate { it.first to it.second }
        val assignments = HashMap<UUID, UUID>()
        for ((segmentID, label) in assignment) byLabel[label]?.id?.let { assignments[segmentID] = it }
        store.saveSpeakers(speakers.map { it.second }, assignments, id)
    }

    private suspend fun recognize(speakers: MutableList<Pair<String, Speaker>>, prints: List<VoicePrint>) {
        if (prints.isEmpty()) return
        val people = store.people()
        val scores = speakers.map { labeled -> prints.map { VoiceMatcher.similarity(labeled.second.embedding, it.embedding) } }
        val pairs = mutableListOf<Candidate>()
        for (index in speakers.indices) {
            prints.forEachIndexed { column, print ->
                if (scores[index][column] >= VoiceMatcher.SUGGEST_THRESHOLD) pairs.add(Candidate(index, print.personID, scores[index][column]))
            }
        }
        val named = HashSet<Int>()
        val taken = HashSet<UUID>()
        for (pair in pairs.sortedWith(Candidate.closer)) {
            if (pair.index in named || pair.person in taken) continue
            // The lead is measured against people still free: someone already given to a closer voice is no rival.
            val rival = prints.indices
                .filter { prints[it].personID != pair.person && prints[it].personID !in taken }
                .maxOfOrNull { scores[pair.index][it] } ?: -1f
            if (pair.score - rival < VoiceMatcher.MINIMUM_MARGIN) continue
            named.add(pair.index)
            taken.add(pair.person)
            val (label, speaker) = speakers[pair.index]
            speakers[pair.index] = label to speaker.copy(
                personID = pair.person,
                name = people.firstOrNull { it.id == pair.person }?.name,
                isSuggested = true,
            )
        }
    }

    private data class Candidate(val index: Int, val person: UUID, val score: Float) {
        companion object {
            /** Highest score first, then a fixed order, so that the same meeting always gets the same names. */
            val closer = Comparator<Candidate> { lhs, rhs ->
                when {
                    lhs.score != rhs.score -> rhs.score.compareTo(lhs.score)
                    lhs.index != rhs.index -> lhs.index.compareTo(rhs.index)
                    else -> lhs.person.uuidString.compareTo(rhs.person.uuidString)
                }
            }
        }
    }

    companion object {
        /** A voice heard for less than this in a whole recording does not become a speaker. */
        const val LEAST_SPEECH: TimeInterval = 2.0

        /** Drops voices heard too little to be a person. Their moments go to whoever else was speaking then. */
        fun withoutPassingSounds(turns: List<SpeakerTurn>): List<SpeakerTurn> {
            val talk = HashMap<String, Double>()
            for (turn in turns) talk[turn.speaker] = (talk[turn.speaker] ?: 0.0) + (turn.end - turn.start)
            val kept = turns.filter { (talk[it.speaker] ?: 0.0) >= LEAST_SPEECH }
            // With nothing left, the short sounds are all there is, and some speaker beats none.
            return kept.ifEmpty { turns }
        }

        /** Numbered by who spoke first, which is how people read a transcript. */
        private fun speakers(turns: List<SpeakerTurn>, id: RecordingID): List<Pair<String, Speaker>> {
            val order = mutableListOf<String>()
            for (turn in turns.sortedBy { it.start }) if (turn.speaker !in order) order.add(turn.speaker)
            return order.mapIndexed { index, label ->
                val own = turns.filter { it.speaker == label }
                label to Speaker(recordingID = id, number = index + 1, embedding = centroid(own), talkTime = own.sumOf { it.end - it.start })
            }
        }

        /** Embeddings are raw, so each turn is normalized before it counts, by its length in time. */
        fun centroid(turns: List<SpeakerTurn>): List<Float> {
            val size = turns.firstOrNull { it.embedding.isNotEmpty() }?.embedding?.size ?: return emptyList()
            val sum = FloatArray(size)
            for (turn in turns) {
                if (turn.embedding.size != size) continue
                val weight = (turn.end - turn.start).toFloat()
                val unit = VoiceMatcher.normalized(turn.embedding)
                for (index in sum.indices) sum[index] += unit[index] * weight
            }
            return VoiceMatcher.normalized(sum.toList())
        }
    }
}

class SpeakerException(val reason: Reason) : Exception(reason.name) {
    enum class Reason { TOO_LITTLE_SPEECH, NO_EMBEDDING }
}

/** What a person can do with speakers and saved voices. */
class SpeakerService(
    private val store: SpeakerStore,
    private val modelID: suspend () -> String?,
    private val now: () -> Instant = { Instant.now() },
) {
    companion object {
        /** Below this, a voice print would be unreliable. */
        const val MINIMUM_TALK_TIME: TimeInterval = 10.0
    }

    suspend fun rename(speaker: Speaker, name: String) {
        val trimmed = name.trimmedWhitespace()
        store.update(speaker.copy(name = trimmed.ifEmpty { null }, personID = null, isSuggested = false))
    }

    suspend fun assign(speaker: Speaker, person: Person) {
        store.update(speaker.copy(name = person.name, personID = person.id, isSuggested = false))
    }

    suspend fun setSpeaker(speaker: Speaker, segmentID: UUID) = store.setSpeaker(speaker.id, segmentID)

    suspend fun merge(source: Speaker, target: Speaker) = store.merge(source.id, target.id)

    /** Accepting a suggestion also teaches the voice print, so recognition gets better with use. */
    suspend fun confirm(speaker: Speaker) {
        val personID = speaker.personID ?: return
        val updated = speaker.copy(isSuggested = false)
        store.update(updated)
        learn(updated, personID)
    }

    /** Creates a person from this speaker's voice. The caller must already have the person's consent. */
    suspend fun saveVoicePrint(speaker: Speaker, name: String): Person {
        if (speaker.talkTime < MINIMUM_TALK_TIME) throw SpeakerException(SpeakerException.Reason.TOO_LITTLE_SPEECH)
        val model = modelID()
        if (speaker.embedding.isEmpty() || model == null) throw SpeakerException(SpeakerException.Reason.NO_EMBEDDING)
        val person = Person(name = name.trimmedWhitespace(), createdAt = now())
        store.insert(person)
        store.save(VoicePrint(person.id, model, speaker.embedding, speaker.talkTime))
        assign(speaker, person)
        return person
    }

    suspend fun rename(person: Person, name: String) {
        val trimmed = name.trimmedWhitespace()
        if (trimmed.isEmpty()) return
        store.update(person.copy(name = trimmed))
    }

    suspend fun delete(person: Person) = store.deletePerson(person.id)

    /** For the same person saved twice. Their meetings keep working, under the name that stays. */
    suspend fun merge(source: Person, target: Person) {
        if (source.id == target.id) return
        store.mergePerson(source.id, target)
    }

    suspend fun recordings(person: Person): List<RecordingID> = store.recordings(person.id)

    private suspend fun learn(speaker: Speaker, personID: UUID) {
        val model = modelID() ?: return
        if (speaker.embedding.isEmpty()) return
        val existing = store.voicePrints(model).firstOrNull { it.personID == personID } ?: return
        store.save(
            VoicePrint(
                personID, model,
                VoiceMatcher.blend(existing.embedding, existing.talkTime, speaker.embedding, speaker.talkTime),
                existing.talkTime + speaker.talkTime,
            ),
        )
    }
}

/** Which speaker said each phrase: the one who overlaps it the most. */
object SpeakerAlignment {
    fun assign(segments: List<TranscriptSegment>, turns: List<SpeakerTurn>): Map<UUID, String> {
        val result = HashMap<UUID, String>()
        for (segment in segments) {
            val talked = HashMap<String, Double>()
            for (turn in turns) {
                if (turn.end > segment.start && turn.start < segment.end) {
                    talked[turn.speaker] = (talked[turn.speaker] ?: 0.0) + (minOf(turn.end, segment.end) - maxOf(turn.start, segment.start))
                }
            }
            // The most overlap, and on a tie the label that sorts first, as the Swift comparison does.
            talked.entries.maxWithOrNull { lhs, rhs ->
                if (lhs.value == rhs.value) rhs.key.compareTo(lhs.key) else lhs.value.compareTo(rhs.value)
            }?.let { result[segment.id] = it.key }
        }
        return result
    }
}

/** How much one speaker took part in a meeting. */
data class SpeakerStat(
    val speakerID: UUID,
    /** The length of the phrases given to this speaker. */
    val talkTime: TimeInterval,
    /** Of the speech given to anyone, from 0 to 1. */
    val share: Double,
    /** Times this speaker took the floor: phrases in a row by the same voice count once. */
    val turns: Int,
    val longestTurn: TimeInterval,
) {
    val id: UUID get() = speakerID
}

object SpeakerStats {
    private data class Turn(val speaker: String, val start: TimeInterval, val end: TimeInterval)

    /** Read from the transcript, so that merging speakers or moving a phrase changes the numbers too. */
    fun compute(speakers: List<Speaker>, segments: List<TranscriptSegment>): List<SpeakerStat> {
        val known = speakers.map { it.id.uuidString }.toSet()
        val talk = HashMap<String, Double>()
        val turns = HashMap<String, Int>()
        val longest = HashMap<String, Double>()
        var current: Turn? = null
        fun closeTurn() {
            val turn = current ?: return
            turns[turn.speaker] = (turns[turn.speaker] ?: 0) + 1
            longest[turn.speaker] = maxOf(longest[turn.speaker] ?: 0.0, turn.end - turn.start)
            current = null
        }
        for (segment in segments.sortedBy { it.start }) {
            val speaker = segment.speaker
            if (speaker == null || speaker !in known) {
                // A phrase nobody said still breaks a turn.
                closeTurn()
                continue
            }
            talk[speaker] = (talk[speaker] ?: 0.0) + maxOf(0.0, segment.end - segment.start)
            val turn = current
            if (turn != null && turn.speaker == speaker) {
                current = Turn(speaker, turn.start, maxOf(turn.end, segment.end))
            } else {
                closeTurn()
                current = Turn(speaker, segment.start, segment.end)
            }
        }
        closeTurn()
        val total = talk.values.sum()
        if (total <= 0) return emptyList()
        return speakers.mapNotNull { speaker ->
            val key = speaker.id.uuidString
            val time = talk[key]?.takeIf { it > 0 } ?: return@mapNotNull null
            speaker.number to SpeakerStat(speaker.id, time, time / total, turns[key] ?: 0, longest[key] ?: 0.0)
        }.sortedWith { a, b ->
            if (a.second.talkTime != b.second.talkTime) b.second.talkTime.compareTo(a.second.talkTime) else a.first.compareTo(b.first)
        }.map { it.second }
    }
}

sealed interface VoiceMatch {
    /** Close enough to show the name as a suggestion. */
    data class Suggested(val personID: UUID, val score: Float) : VoiceMatch
    /** Too close to ignore, too far to name. Keeps "Speaker N". */
    data class Uncertain(val personID: UUID, val score: Float) : VoiceMatch
    data object Unknown : VoiceMatch
}

/**
 * Compares voices. A wrong name in a meeting record is worse than no name, so a name needs both a close score and a
 * clear lead over the next person.
 */
object VoiceMatcher {
    const val SUGGEST_THRESHOLD = 0.6f
    const val UNCERTAIN_THRESHOLD = 0.45f
    /** Two saved people this close to one voice is a coin toss, and a coin toss is not a name. */
    const val MINIMUM_MARGIN = 0.08f

    /** Unit length, so that a loud or long stretch does not outweigh the others. Zero stays zero. */
    fun normalized(vector: List<Float>): List<Float> {
        val length = kotlin.math.sqrt(vector.fold(0f) { sum, value -> sum + value * value })
        return if (length > 0) vector.map { it / length } else vector
    }

    fun similarity(lhs: List<Float>, rhs: List<Float>): Float {
        if (lhs.size != rhs.size || lhs.isEmpty()) return 0f
        var dot = 0f
        var left = 0f
        var right = 0f
        for (index in lhs.indices) {
            dot += lhs[index] * rhs[index]
            left += lhs[index] * lhs[index]
            right += rhs[index] * rhs[index]
        }
        val scale = kotlin.math.sqrt(left * right)
        return if (scale > 0) dot / scale else 0f
    }

    fun match(embedding: List<Float>, prints: List<VoicePrint>): VoiceMatch {
        val scored = prints.map { it.personID to similarity(embedding, it.embedding) }
        val best = scored.maxByOrNull { it.second } ?: return VoiceMatch.Unknown
        val runnerUp = scored.filter { it.first != best.first }.maxOfOrNull { it.second } ?: -1f
        if (best.second >= SUGGEST_THRESHOLD && best.second - runnerUp >= MINIMUM_MARGIN) return VoiceMatch.Suggested(best.first, best.second)
        if (best.second >= UNCERTAIN_THRESHOLD) return VoiceMatch.Uncertain(best.first, best.second)
        return VoiceMatch.Unknown
    }

    /** The average of two embeddings, weighted by how much speech each one saw. Both sides are normalized first. */
    fun blend(lhs: List<Float>, leftWeight: TimeInterval, rhs: List<Float>, rightWeight: TimeInterval): List<Float> {
        if (lhs.size != rhs.size || leftWeight + rightWeight <= 0) return rhs
        val left = (leftWeight / (leftWeight + rightWeight)).toFloat()
        return normalized(normalized(lhs).zip(normalized(rhs)).map { (l, r) -> l * left + r * (1 - left) })
    }
}

/** Whether the voices a diarizer found are clearly different people (D-081). */
object VoiceSeparation {
    /** Voices whose prints are closer than this might be one person. */
    const val DISTINCT = 0.5f
    /** The most speakers tried without being asked. */
    const val MOST_SPEAKERS = 8

    /** The similarity of the two closest voices, from each one's blended print. Null with fewer than two voices. */
    fun closestPair(turns: List<SpeakerTurn>): Float? {
        val voices = turns.groupBy { it.speaker }.values.map { SpeakerPipeline.centroid(it) }
        var closest: Float? = null
        for (first in voices.indices) for (second in voices.indices) {
            if (second <= first) continue
            val score = VoiceMatcher.similarity(voices[first], voices[second])
            closest = maxOf(closest ?: score, score)
        }
        return closest
    }

    /** Whether every pair of voices is clearly apart. */
    fun areDistinct(turns: List<SpeakerTurn>): Boolean = (closestPair(turns) ?: -1f) < DISTINCT
}
