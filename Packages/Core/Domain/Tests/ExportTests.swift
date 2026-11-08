@testable import Domain
import Foundation
import Testing

private let id = RecordingID()
private let ana = Speaker(recordingID: id, number: 1, name: "Ana", embedding: [1], talkTime: 1)
private let segments = [
    TranscriptSegment(recordingID: id, start: 1.5, end: 3, text: "Hello", speaker: ana.id.uuidString),
    TranscriptSegment(recordingID: id, start: 3661.25, end: 3662, text: "Bye"),
]

struct TranscriptExporterTests {
    private func text(_ format: TranscriptFormat, _ options: ExportOptions = ExportOptions()) -> String {
        TranscriptExporter.text(title: "Sync", segments: segments, speakers: [ana], format: format, options: options)
    }

    @Test func `plain text carries what was asked for`() {
        #expect(text(.txt) == "[00:01] Ana: Hello\n[1:01:01] Bye\n")
        #expect(text(.txt, ExportOptions(includesSpeakers: false)) == "[00:01] Hello\n[1:01:01] Bye\n")
        #expect(text(.txt, ExportOptions(includesTimestamps: false)) == "Ana: Hello\nBye\n")
    }

    @Test func `markdown has a title and bold names`() {
        #expect(text(.markdown) == "# Sync\n\n[00:01] **Ana:** Hello\n\n[1:01:01] Bye\n")
    }

    @Test func `SRT uses a comma, counts from one, and keeps cues apart`() {
        #expect(text(.srt) == """
        1
        00:00:01,500 --> 00:00:03,000
        Ana: Hello

        2
        01:01:01,250 --> 01:01:02,000
        Bye

        """)
    }

    @Test func `VTT starts with its header and uses a dot`() {
        #expect(text(.vtt).hasPrefix("WEBVTT\n\n00:00:01.500 --> 00:00:03.000\nAna: Hello\n\n"))
    }

    @Test func `subtitles keep their times even with timestamps off`() {
        #expect(text(.srt, ExportOptions(includesTimestamps: false)).contains("-->"))
    }

    @Test func `a blank line inside a phrase cannot end a cue early`() {
        let odd = [TranscriptSegment(recordingID: id, start: 0, end: 1, text: "One\n\nTwo")]
        let result = TranscriptExporter.text(title: "T", segments: odd, speakers: [], format: .vtt)
        #expect(result.hasSuffix("One Two\n"))
    }
}

struct SummaryExporterTests {
    @Test func `sections, tasks, names, and sources all come through`() {
        let token = SpeakerTokens.encode("Ana", speakers: [ana])
        let summary = Summary(
            recordingID: id, templateName: "T", modelID: "m", language: nil,
            sections: [
                SummarySection(title: "Points", kind: .bullets, items: [SummaryItem(text: "A point", sourceTime: 75)]),
                SummarySection(title: "Tasks", kind: .tasks, items: [
                    SummaryItem(text: "Send it", owner: token, due: "Friday", isDone: true),
                ]),
            ],
            createdAt: .now,
        )
        #expect(SummaryExporter.markdown(title: "Sync", summary: summary, speakers: [ana]) == """
        # Sync

        ## Points

        - A point [01:15]

        ## Tasks

        - [x] Ana: Send it (Friday)


        """)
    }
}

struct ExportFileNameTests {
    @Test(arguments: [
        ("Sync", "Sync.txt"), ("Q1/Q2: plan?", "Q1 Q2  plan.txt"), ("../../etc", "etc.txt"), ("", "Meeting.txt"),
        ("   ", "Meeting.txt"), ("議事録", "議事録.txt"),
    ])
    func `a title becomes a safe name`(title: String, name: String) {
        #expect(ExportFileName.safe(title, fileExtension: "txt") == name)
    }
}

struct AppLockStateTests {
    @Test func `off means it never gets in the way`() {
        var lock = AppLockState(isEnabled: false)
        lock.becameInactive()
        lock.enteredBackground()
        #expect(!lock.isLocked)
        #expect(!lock.isCovered)
        let step1 = lock.becameActive()
        #expect(!step1)
    }

    @Test func `content is covered before the app switcher takes its picture`() {
        var lock = AppLockState(isEnabled: true)
        lock.finishAuthentication(success: true)
        lock.becameInactive()
        #expect(lock.isCovered)
        #expect(!lock.isLocked)
        let step2 = lock.becameActive()
        #expect(!step2)
        #expect(!lock.isCovered)
    }

    @Test func `leaving locks it, and coming back asks once`() {
        var lock = AppLockState(isEnabled: true)
        lock.finishAuthentication(success: true)
        lock.enteredBackground()
        #expect(lock.isLocked)
        let step3 = lock.becameActive()
        #expect(step3)
        let step4 = lock.becameActive()
        #expect(!step4)
    }

    @Test func `the Face ID screen itself does not lock the app or ask again`() {
        var lock = AppLockState(isEnabled: true)
        let step5 = lock.becameActive()
        #expect(step5)
        lock.becameInactive()
        let step6 = lock.becameActive()
        #expect(!step6)
        lock.finishAuthentication(success: true)
        lock.becameInactive()
        #expect(!lock.isLocked)
        let step7 = lock.becameActive()
        #expect(!step7)
        #expect(!lock.isCovered)
    }

    @Test func `after a cancel it stays locked, stops asking, and the button asks`() {
        var lock = AppLockState(isEnabled: true)
        let step8 = lock.becameActive()
        #expect(step8)
        lock.finishAuthentication(success: false)
        lock.becameInactive()
        let step9 = lock.becameActive()
        #expect(!step9)
        #expect(lock.isLocked)
        let step10 = lock.requestUnlock()
        #expect(step10)
        let step11 = lock.requestUnlock()
        #expect(!step11)
    }

    @Test func `turning it off opens everything`() {
        var lock = AppLockState(isEnabled: true)
        lock.setEnabled(false)
        #expect(!lock.isLocked)
        #expect(!lock.isCovered)
    }
}
