import Foundation

/// What a person sees before a long transcription starts.
public extension L10n.Transcript {
    static var waitingForPower: String { L10n.text("transcript.waiting_power") }
    static var planTitle: String { L10n.text("transcript.plan_title") }
    static var planUnknownTime: String { L10n.text("transcript.plan_unknown_time") }
    static var startNow: String { L10n.text("transcript.start_now") }
    static var startWhenCharging: String { L10n.text("transcript.start_when_charging") }
    static func planMinutes(_ minutes: Int) -> String {
        String(format: L10n.text("transcript.plan_minutes"), minutes)
    }

    static func planMinutesRange(_ low: Int, _ high: Int) -> String {
        String(format: L10n.text("transcript.plan_minutes_range"), low, high)
    }
}

/// Feedback shared by every piece of long work: steps, elapsed time, and time left.
public extension L10n {
    enum Feedback {
        public static var stepWaiting: String { L10n.text("feedback.step_waiting") }
        public static var stepActive: String { L10n.text("feedback.step_active") }
        public static var stepDone: String { L10n.text("feedback.step_done") }
        public static func elapsed(_ time: String) -> String {
            String(format: L10n.text("feedback.elapsed"), time)
        }

        public static func remaining(_ time: String) -> String {
            String(format: L10n.text("feedback.remaining"), time)
        }
    }
}

/// The card shown while a meeting is transcribed.
public extension L10n.Transcript {
    static var workingTitle: String { L10n.text("transcript.working_title") }
    static var stepPrepare: String { L10n.text("transcript.step_prepare") }
    static var stepTranscribe: String { L10n.text("transcript.step_transcribe") }
    static var stepSpeakers: String { L10n.text("transcript.step_speakers") }
    static var prepareNote: String { L10n.text("transcript.prepare_note") }
    static var speakersNote: String { L10n.text("transcript.speakers_note") }
    static var queuedNote: String { L10n.text("transcript.queued_note") }
    static var deviceNote: String { L10n.text("transcript.device_note") }
    static var powerNote: String { L10n.text("transcript.power_note") }
    static var leaveNote: String { L10n.text("transcript.leave_note") }
    static var interrupted: String { L10n.text("transcript.interrupted") }
    static var interruptedNote: String { L10n.text("transcript.interrupted_note") }
}

/// Separating voices again with a known count.
public extension L10n.Detail {
    static var speakersOne: String { L10n.text("detail.speakers_one") }
    static var speakersWrong: String { L10n.text("detail.speakers_wrong") }
    static var speakersRedetect: String { L10n.text("detail.speakers_redetect") }
    static var speakersCountTitle: String { L10n.text("detail.speakers_count_title") }
    static var speakersCountAuto: String { L10n.text("detail.speakers_count_auto") }
    static var speakersRedetectNote: String { L10n.text("detail.speakers_redetect_note") }
    static func speakersCountPeople(_ count: Int) -> String {
        String(format: L10n.text("detail.speakers_count_people"), count)
    }
}

/// The storage bars.
public extension L10n.System {
    static var usageFree: String { L10n.text("system.usage_free") }
    static func usageInUse(_ size: String) -> String {
        String(format: L10n.text("system.usage_in_use"), size)
    }
}

public extension L10n.Models {
    static func storageTotal(_ size: String) -> String {
        String(format: L10n.text("models.storage_total"), size)
    }
}
