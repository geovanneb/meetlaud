package com.meetlaud.app

import com.meetlaud.app.infra.persistence.DatabaseStore
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
 */
object Showcase {
    /** What the scripted model answers, in order. */
    val answers = listOf(
        "Two decisions: the print ads are dropped and their budget moves to video [7], and the launch stays on March 3 [10].",
    )

    private class Line(val time: Double, val speaker: Int, val text: String)

    private val lines = listOf(
        Line(0.0, 1, "Thanks for joining. Let's lock the plan for the spring campaign today."),
        Line(9.0, 2, "I shared the draft. The main idea is short videos first, then email."),
        Line(21.0, 3, "Customers asked for real stories, so I'd lead with two customer videos."),
        Line(34.0, 1, "Agreed. What does that do to the budget?"),
        Line(41.0, 2, "Video takes about forty percent. We can drop the print ads to cover it."),
        Line(55.0, 3, "Print brought almost no sign-ups last year, so I'm fine with that."),
        Line(66.0, 1, "Then it's decided: no print, and the budget moves to video."),
        Line(78.0, 2, "I can have the first script ready by Friday."),
        Line(87.0, 3, "I'll ask Harbor Bikes if they want to be the first story."),
        Line(98.0, 1, "Great. Launch date stays March 3. Let's review progress next Tuesday."),
    )

    suspend fun seed(store: DatabaseStore) {
        if (store.observeRecordingsOnce().isNotEmpty()) return
        val now = Instant.now()
        val marketing = Folder(name = "Marketing", createdAt = now)
        val clients = Folder(name = "Clients", createdAt = now)
        store.insert(marketing)
        store.insert(clients)

        val launch = Recording(
            title = "Spring campaign kickoff", createdAt = now.minusSeconds(1800), duration = 2880.0,
            folderID = marketing.id, attendees = listOf("Ana Ribeiro", "Kenji Sato", "Sofía Morales"),
        )
        store.insert(launch)
        listOf(
            Recording(title = "Interview with Harbor Bikes", createdAt = now.minusSeconds(26000), duration = 1500.0, folderID = clients.id),
            Recording(title = "Weekly design sync", createdAt = now.minusSeconds(90000), duration = 1920.0, folderID = marketing.id),
            Recording(title = "Budget review", createdAt = now.minusSeconds(176_000), duration = 3300.0),
            Recording(title = "1:1 with Kenji", createdAt = now.minusSeconds(260_000), duration = 1080.0),
            Recording(title = "Partner call: Bluefin Studio", createdAt = now.minusSeconds(350_000), duration = 2460.0, folderID = clients.id),
        ).forEach { store.insert(it) }
        store.insert(Marker(recordingID = launch.id, time = 312.0, kind = MarkerKind.NOTE, text = "Budget agreed"))
        store.insert(Marker(recordingID = launch.id, time = 1260.0, kind = MarkerKind.FLAG))

        val people = listOf("Ana Ribeiro", "Kenji Sato", "Sofía Morales")
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
        store.append(segments, TranscriptionJob(launch.id, "fake-small", "en"))
        store.deleteJob(launch.id)
        store.save(Transcript(launch.id, "fake-small", "en", isComplete = true))
        // Assignments go by the speaker column already on each phrase, as on iOS.
        store.saveSpeakers(found, segments.associate { segment -> segment.id to found.first { it.id.uuidString == segment.speaker }.id }, launch.id)
        store.save(
            Summary(
                recordingID = launch.id, templateName = "Meeting", modelID = "fake-chat", language = "en", isComplete = true, createdAt = now,
                sections = listOf(
                    SummarySection("Key points", SectionKind.BULLETS, listOf(
                        SummaryItem(text = "The campaign leads with short customer videos, then email.", sourceTime = 9.0),
                        SummaryItem(text = "Customers asked for real stories in the last survey.", sourceTime = 21.0),
                        SummaryItem(text = "Print ads brought almost no sign-ups last year.", sourceTime = 55.0),
                    )),
                    SummarySection("Decisions", SectionKind.BULLETS, listOf(
                        SummaryItem(text = "No print ads. Their budget moves to video.", sourceTime = 66.0),
                        SummaryItem(text = "Launch stays on March 3.", sourceTime = 98.0),
                    )),
                    SummarySection("Action items", SectionKind.TASKS, listOf(
                        SummaryItem(text = "First video script", sourceTime = 78.0, owner = "Kenji Sato", due = "Friday"),
                        SummaryItem(text = "Invite Harbor Bikes as the first story", sourceTime = 87.0, owner = "Sofía Morales"),
                        SummaryItem(text = "Progress review", sourceTime = 98.0, owner = "Ana Ribeiro", due = "Tuesday"),
                    )),
                ),
            ),
        )
    }
}
