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
