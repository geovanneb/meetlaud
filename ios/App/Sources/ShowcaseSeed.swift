import Domain
import Foundation
import TestSupport

/// Fictional meetings for screenshots and demos, used with `--showcase`. Every person, company, and number here is
/// invented. Nothing is real, so the pictures can be shared anywhere.
enum ShowcaseSeed {
    /// What the scripted model answers, in order.
    static let answers = [
        "Two decisions: the print ads are dropped and their budget moves to video [7], "
            + "and the launch stays on March 3 [10].",
    ]

    private struct Line {
        let time: TimeInterval
        let speaker: Int
        let text: String
    }

    static func seed(
        _ store: InMemoryRecordingStore,
        transcripts: FakeTranscriptStore,
        speakers: FakeSpeakerStore,
        summaries: FakeSummaryStore,
    ) async {
        let now = Date()
        let marketing = Folder(name: "Marketing", createdAt: now)
        let clients = Folder(name: "Clients", createdAt: now)
        await store.insert(marketing)
        await store.insert(clients)

        let launch = Recording(
            title: "Spring campaign kickoff", createdAt: now.addingTimeInterval(-1800), duration: 2880,
            folderID: marketing.id, attendees: ["Ana Ribeiro", "Kenji Sato", "Sofía Morales"],
        )
        await store.insert(launch)
        let others: [Recording] = [
            Recording(
                title: "Interview with Harbor Bikes",
                createdAt: now.addingTimeInterval(-26000),
                duration: 1500,
                folderID: clients.id,
            ),
            Recording(
                title: "Weekly design sync",
                createdAt: now.addingTimeInterval(-90000),
                duration: 1920,
                folderID: marketing.id,
            ),
            Recording(title: "Budget review", createdAt: now.addingTimeInterval(-176_000), duration: 3300),
            Recording(title: "1:1 with Kenji", createdAt: now.addingTimeInterval(-260_000), duration: 1080),
            Recording(
                title: "Partner call: Bluefin Studio",
                createdAt: now.addingTimeInterval(-350_000),
                duration: 2460,
                folderID: clients.id,
            ),
        ]
        for recording in others {
            await store.insert(recording)
        }
        await store.insert(Marker(recordingID: launch.id, time: 312, kind: .note, text: "Budget agreed"))
        await store.insert(Marker(recordingID: launch.id, time: 1260, kind: .flag))
        await seedConversation(of: launch, transcripts: transcripts, speakers: speakers)
        await summaries.save(summary(of: launch.id, at: now))
    }

    private static let lines: [Line] = [
        Line(time: 0, speaker: 1, text: "Thanks for joining. Let's lock the plan for the spring campaign today."),
        Line(time: 9, speaker: 2, text: "I shared the draft. The main idea is short videos first, then email."),
        Line(time: 21, speaker: 3, text: "Customers asked for real stories, so I'd lead with two customer videos."),
        Line(time: 34, speaker: 1, text: "Agreed. What does that do to the budget?"),
        Line(time: 41, speaker: 2, text: "Video takes about forty percent. We can drop the print ads to cover it."),
        Line(time: 55, speaker: 3, text: "Print brought almost no sign-ups last year, so I'm fine with that."),
        Line(time: 66, speaker: 1, text: "Then it's decided: no print, and the budget moves to video."),
        Line(time: 78, speaker: 2, text: "I can have the first script ready by Friday."),
        Line(time: 87, speaker: 3, text: "I'll ask Harbor Bikes if they want to be the first story."),
        Line(time: 98, speaker: 1, text: "Great. Launch date stays March 3. Let's review progress next Tuesday."),
    ]

    private static func seedConversation(
        of recording: Recording,
        transcripts: FakeTranscriptStore,
        speakers: FakeSpeakerStore,
    ) async {
        let people = ["Ana Ribeiro", "Kenji Sato", "Sofía Morales"]
        let found = people.enumerated().map { index, name in
            Speaker(
                recordingID: recording.id, number: index + 1, name: name, embedding: [Float(index), 1],
                talkTime: [1140, 960, 780][index],
            )
        }
        for name in people {
            await speakers.insert(Person(name: name, createdAt: .now))
        }
        let segments = lines.enumerated().map { index, line in
            TranscriptSegment(
                recordingID: recording.id, start: line.time,
                end: index + 1 < lines.count ? lines[index + 1].time : line.time + 10,
                text: line.text, speaker: found[line.speaker - 1].id.uuidString,
            )
        }
        let job = TranscriptionJob(recordingID: recording.id, modelID: "fake-small", language: "en")
        try? await transcripts.append(segments, job: job)
        await transcripts.deleteJob(for: recording.id)
        await transcripts.save(Transcript(
            recordingID: recording.id, modelID: "fake-small", language: "en", isComplete: true,
        ))
        await speakers.saveSpeakers(found, assignments: [:], for: recording.id)
    }

    private static func summary(of id: RecordingID, at date: Date) -> Summary {
        Summary(
            recordingID: id, templateName: "Meeting", modelID: "fake-chat", language: "en",
            sections: [
                SummarySection(title: "Key points", kind: .bullets, items: [
                    SummaryItem(text: "The campaign leads with short customer videos, then email.", sourceTime: 9),
                    SummaryItem(text: "Customers asked for real stories in the last survey.", sourceTime: 21),
                    SummaryItem(text: "Print ads brought almost no sign-ups last year.", sourceTime: 55),
                ]),
                SummarySection(title: "Decisions", kind: .bullets, items: [
                    SummaryItem(text: "No print ads. Their budget moves to video.", sourceTime: 66),
                    SummaryItem(text: "Launch stays on March 3.", sourceTime: 98),
                ]),
                SummarySection(title: "Action items", kind: .tasks, items: [
                    SummaryItem(text: "First video script", sourceTime: 78, owner: "Kenji Sato", due: "Friday"),
                    SummaryItem(text: "Invite Harbor Bikes as the first story", sourceTime: 87, owner: "Sofía Morales"),
                    SummaryItem(text: "Progress review", sourceTime: 98, owner: "Ana Ribeiro", due: "Tuesday"),
                ]),
            ],
            isComplete: true, createdAt: date,
        )
    }
}
