import Foundation

// A table of strings grows with the app, and has no logic to split.
// swiftlint:disable type_body_length
/// All user-facing text. Keys live in Resources/Localizable.xcstrings, in en, ja, pt-BR, and es.
public enum L10n {
    public enum Nav {
        public static var home: String { text("nav.home") }
        public static var library: String { text("nav.library") }
        public static var ask: String { text("nav.ask") }
        public static var tools: String { text("nav.tools") }
        public static var settings: String { text("nav.settings") }
        public static var help: String { text("nav.help") }
        public static var openMenu: String { text("nav.open_menu") }
        public static var closeMenu: String { text("nav.close_menu") }
    }

    public enum Home {
        public static var add: String { text("home.add") }
        public static var startRecording: String { text("home.start_recording") }
        public static var importFiles: String { text("home.import_files") }
        public static var newChat: String { text("home.new_chat") }
        public static var upcoming: String { text("home.upcoming") }
        public static var calendarView: String { text("home.calendar_view") }
        public static var connect: String { text("home.connect") }
        public static var connectTitle: String { text("home.connect_title") }
        public static var connectMessage: String { text("home.connect_message") }
        public static var noEvents: String { text("home.no_events") }
        public static var noEventsMessage: String { text("home.no_events_message") }
        public static var dayEmpty: String { text("home.day_empty") }
        public static var today: String { text("home.today") }
        public static var calendarExpanded: String { text("home.calendar_expanded") }
        public static var calendarCollapsed: String { text("home.calendar_collapsed") }
        public static var untitledEvent: String { text("home.untitled_event") }
        public static var calendarDenied: String { text("home.calendar_denied") }
        public static var record: String { text("home.record") }
        public static var meetingNotes: String { text("home.meeting_notes") }
        public static var emptyTitle: String { text("home.empty.title") }
        public static var emptyMessage: String { text("home.empty.message") }
        public static var askPlaceholder: String { text("home.ask_placeholder") }
    }

    public enum Recorder {
        public static var statusReady: String { text("recorder.status.ready") }
        public static var statusRecording: String { text("recorder.status.recording") }
        public static var statusPaused: String { text("recorder.status.paused") }
        public static var statusInterrupted: String { text("recorder.status.interrupted") }
        public static var statusFinishing: String { text("recorder.status.finishing") }
        public static var pause: String { text("recorder.pause") }
        public static var resume: String { text("recorder.resume") }
        public static var stop: String { text("recorder.stop") }
        public static var flag: String { text("recorder.flag") }
        public static var photo: String { text("recorder.photo") }
        public static var addNote: String { text("recorder.add_note") }
        public static var notePlaceholder: String { text("recorder.note_placeholder") }
        public static var minimize: String { text("recorder.minimize") }
        public static var microphone: String { text("recorder.microphone") }
        public static var interruptedMessage: String { text("recorder.interrupted_message") }
        public static var storageLow: String { text("recorder.storage_low") }
        public static var startFailed: String { text("recorder.start_failed") }
        public static var recovered: String { text("recorder.recovered") }
        public static var recoveredTitle: String { text("recorder.recovered_title") }
        public static var recoveredMessage: String { text("recorder.recovered_message") }
        public static var consentTitle: String { text("recorder.consent_title") }
        public static var consentMessage: String { text("recorder.consent_message") }
        public static var consentAccept: String { text("recorder.consent_accept") }
        public static var permissionTitle: String { text("recorder.permission_title") }
        public static var permissionMessage: String { text("recorder.permission_message") }
        public static var openSettings: String { text("recorder.open_settings") }

        public static func defaultTitle(_ date: String) -> String {
            String(format: text("recorder.default_title"), date)
        }
    }

    public enum Detail {
        public static var export: String { text("detail.export") }
        public static var exportWhat: String { text("detail.export_what") }
        public static var exportSpeakers: String { text("detail.export_speakers") }
        public static var exportTimestamps: String { text("detail.export_timestamps") }
        public static var exportShare: String { text("detail.export_share") }
        public static var audio: String { text("detail.audio") }
        public static var play: String { text("detail.play") }
        public static var back: String { text("detail.back") }
        public static var forward: String { text("detail.forward") }
        public static var position: String { text("detail.position") }
        public static var speed: String { text("detail.speed") }
        public static var moments: String { text("detail.moments") }
        public static var moment: String { text("detail.moment") }
        public static var section: String { text("detail.section") }
        public static var noMoments: String { text("detail.no_moments") }
        public static var unavailableTitle: String { text("detail.unavailable_title") }
        public static var unavailableMessage: String { text("detail.unavailable_message") }
    }

    public enum Transcript {
        public static var polish: String { text("transcript.polish") }
        public static var earlier: String { text("transcript.earlier") }
        public static var restore: String { text("transcript.restore") }
        public static var restoreTitle: String { text("transcript.restore_title") }
        public static var restoreMessage: String { text("transcript.restore_message") }
        public static var title: String { text("transcript.title") }
        public static var transcribe: String { text("transcript.transcribe") }
        public static var retranscribe: String { text("transcript.retranscribe") }
        public static var detectLanguage: String { text("transcript.detect_language") }
        public static var emptyMessage: String { text("transcript.empty_message") }
        public static var queued: String { text("transcript.queued") }
        public static var preparing: String { text("transcript.preparing") }
        public static var separatingSpeakers: String { text("transcript.separating_speakers") }
        public static var waitingForDevice: String { text("transcript.waiting_device") }

        public static var edit: String { text("transcript.edit") }
        public static var backToCurrent: String { text("transcript.back_to_current") }
        public static var findReplace: String { text("transcript.find_replace") }
        public static var find: String { text("transcript.find") }
        public static var replaceWith: String { text("transcript.replace_with") }
        public static var replaceAll: String { text("transcript.replace_all") }
        public static var autoLabel: String { text("transcript.auto_label") }
        public static var autoAsk: String { text("transcript.auto_ask") }
        public static var autoAlways: String { text("transcript.auto_always") }
        public static var autoNever: String { text("transcript.auto_never") }

        public static func transcribing(_ percent: String) -> String {
            String(format: text("transcript.transcribing"), percent)
        }

        public static func replaced(_ count: Int) -> String {
            String(format: text("transcript.replaced"), count)
        }
    }

    public enum Settings {
        public static var workspace: String { text("settings.workspace") }
        public static var preferences: String { text("settings.preferences") }
        public static var privacy: String { text("settings.privacy") }
    }

    public enum People {
        public static var title: String { text("people.title") }
        public static var emptyTitle: String { text("people.empty_title") }
        public static var emptyMessage: String { text("people.empty_message") }
        public static var footer: String { text("people.footer") }
        public static var suggested: String { text("people.suggested") }
        public static var confirm: String { text("people.confirm") }
        public static var nameSection: String { text("people.name_section") }
        public static var savedPeople: String { text("people.saved_people") }
        public static var mergeSection: String { text("people.merge_section") }
        public static var saveVoice: String { text("people.save_voice") }
        public static var saveVoiceNote: String { text("people.save_voice_note") }
        public static var consentTitle: String { text("people.consent_title") }
        public static var consentAccept: String { text("people.consent_accept") }
        public static var tooLittleSpeech: String { text("people.too_little_speech") }
        public static var saveFailed: String { text("people.save_failed") }
        public static var changeSpeaker: String { text("people.change_speaker") }
        public static var addName: String { text("people.add_name") }
        public static var meetings: String { text("people.meetings") }
        public static var noMeetings: String { text("people.no_meetings") }
        public static var mergeInto: String { text("people.merge_into") }
        public static var pickSaved: String { text("people.pick_saved") }

        public static func rememberVoice(_ name: String) -> String {
            String(format: text("people.remember_voice"), name)
        }

        public static func numbered(_ number: Int) -> String {
            String(format: text("people.numbered"), number)
        }

        public static func suggestion(_ name: String) -> String {
            String(format: text("people.suggestion"), name)
        }

        public static func consentMessage(_ name: String) -> String {
            String(format: text("people.consent_message"), name)
        }
    }

    public enum Models {
        public static var compare: String { text("models.compare") }
        public static var tryTitle: String { text("models.try_title") }
        public static var tryHint: String { text("models.try_hint") }
        public static var tryRun: String { text("models.try_run") }
        public static var tryUse: String { text("models.try_use") }
        public static var tryNoRecording: String { text("models.try_no_recording") }
        public static var tryRecording: String { text("models.try_recording") }
        public static var tryUnreadable: String { text("models.try_unreadable") }

        public static func tryTime(_ seconds: Int) -> String {
            String(format: text("models.try_time"), seconds)
        }

        public static var title: String { text("models.title") }
        public static var suggestions: String { text("models.suggestions") }
        public static var dismiss: String { text("models.dismiss") }
        public static var downloadAll: String { text("models.download_all") }
        public static var priority: String { text("models.priority") }
        public static var prioritySpeed: String { text("models.priority_speed") }
        public static var priorityBalanced: String { text("models.priority_balanced") }
        public static var priorityQuality: String { text("models.priority_quality") }
        public static var functions: String { text("models.functions") }
        public static var storage: String { text("models.storage") }
        public static var storageNote: String { text("models.storage_note") }
        public static var noModels: String { text("models.no_models") }
        public static var networkActivity: String { text("models.network_activity") }
        public static var networkEmptyTitle: String { text("models.network_empty_title") }
        public static var networkNote: String { text("models.network_note") }
        public static var notInstalled: String { text("models.not_installed") }
        public static var mode: String { text("models.mode") }
        public static var automatic: String { text("models.automatic") }
        public static var showAll: String { text("models.show_all") }
        public static var managedByIOS: String { text("models.managed_by_ios") }
        public static var fit: String { text("models.fit") }
        public static var speed: String { text("models.speed") }
        public static var size: String { text("models.size") }
        public static var languages: String { text("models.languages") }
        public static var license: String { text("models.license") }
        public static var qualityProvisional: String { text("models.quality_provisional") }
        public static var deleteConfirm: String { text("models.delete_confirm") }
        public static var install: String { text("models.install") }
        public static var download: String { text("models.download") }
        public static var speedTest: String { text("models.speed_test") }
        public static var history: String { text("models.history") }
        public static var runStopped: String { text("models.run_stopped") }
        public static var testing: String { text("models.testing") }
        public static var testFailed: String { text("models.test_failed") }
        public static var testBusy: String { text("models.test_busy") }
        public static var quickTest: String { text("models.quick_test") }
        public static var sustainedTest: String { text("models.sustained_test") }
        public static var sustainedHint: String { text("models.sustained_hint") }
        public static var spokenLanguages: String { text("models.spoken_languages") }
        public static var setupTitle: String { text("models.setup_title") }
        public static var setupNote: String { text("models.setup_note") }
        public static var customize: String { text("models.customize") }
        public static var notNow: String { text("models.not_now") }
        public static var roleTranscription: String { text("models.role_transcription") }
        public static var roleSpeakers: String { text("models.role_speakers") }
        public static var roleVoicePrint: String { text("models.role_voice_print") }
        public static var roleChat: String { text("models.role_chat") }
        public static var comingLater: String { text("models.coming_later") }
        public static func searchSpeed(_ seconds: Int) -> String {
            String(format: text("models.search_speed"), seconds)
        }

        public static func writingSpeed(_ words: Int) -> String {
            String(format: text("models.writing_speed"), words)
        }

        public static var roleSearch: String { text("models.role_search") }
        public static var purposeTranscription: String { text("models.purpose_transcription") }
        public static var purposeSpeakers: String { text("models.purpose_speakers") }
        public static var purposeVoicePrint: String { text("models.purpose_voice_print") }
        public static var purposeChat: String { text("models.purpose_chat") }
        public static var purposeSearch: String { text("models.purpose_search") }
        public static var fitBest: String { text("models.fit_best") }
        public static var fitGood: String { text("models.fit_good") }
        public static var fitSlow: String { text("models.fit_slow") }
        public static var fitNotRecommended: String { text("models.fit_not_recommended") }
        public static var fitUnsupported: String { text("models.fit_unsupported") }
        public static var reasonBest: String { text("models.reason_best") }
        public static var reasonWorks: String { text("models.reason_works") }
        public static var reasonSlow: String { text("models.reason_slow") }
        public static var reasonMemory: String { text("models.reason_memory") }
        public static var reasonUnstable: String { text("models.reason_unstable") }
        public static var speedUnknown: String { text("models.speed_unknown") }
        public static var nowGreat: String { text("models.now_great") }
        public static var nowGood: String { text("models.now_good") }
        public static var nowLimited: String { text("models.now_limited") }
        public static var nowPaused: String { text("models.now_paused") }
        public static var conditionWarm: String { text("models.condition_warm") }
        public static var conditionHot: String { text("models.condition_hot") }
        public static var conditionLowPower: String { text("models.condition_low_power") }
        public static var conditionLowBattery: String { text("models.condition_low_battery") }
        public static var conditionLowMemory: String { text("models.condition_low_memory") }
        public static var stateQueued: String { text("models.state_queued") }
        public static var statePaused: String { text("models.state_paused") }
        public static var stateWaitingWiFi: String { text("models.state_waiting_wifi") }
        public static var stateVerifying: String { text("models.state_verifying") }
        public static var statePreparing: String { text("models.state_preparing") }
        public static var stateTesting: String { text("models.state_testing") }
        public static var stateReady: String { text("models.state_ready") }
        public static var failedSpace: String { text("models.failed_space") }
        public static var failedDamaged: String { text("models.failed_damaged") }
        public static var failedUnavailable: String { text("models.failed_unavailable") }
        public static var failedPrepare: String { text("models.failed_prepare") }

        public static func reasonLanguage(_ name: String) -> String {
            String(format: text("models.reason_language"), name)
        }

        public static func speedMeasured(_ minutes: Int) -> String {
            String(format: text("models.speed_measured"), minutes)
        }

        public static func speedEstimated(_ low: Int, _ high: Int) -> String {
            String(format: text("models.speed_estimated"), low, high)
        }

        public static func deviceSummary(_ memory: String, _ free: String) -> String {
            String(format: text("models.device_summary"), memory, free)
        }

        public static func automaticUsing(_ name: String) -> String {
            String(format: text("models.automatic_using"), name)
        }

        public static func stateDownloading(_ received: String, _ total: String) -> String {
            String(format: text("models.state_downloading"), received, total)
        }

        public static func setupFor(_ name: String) -> String {
            String(format: text("models.setup_for"), name)
        }

        public static func setupSize(_ size: String, _ free: String) -> String {
            String(format: text("models.setup_size"), size, free)
        }

        public static func suggestBetter(_ name: String) -> String {
            String(format: text("models.suggest_better"), name)
        }

        public static func suggestLanguage(_ name: String) -> String {
            String(format: text("models.suggest_language"), name)
        }

        public static func suggestUnstable(_ name: String) -> String {
            String(format: text("models.suggest_unstable"), name)
        }

        public static func suggestSlow(_ name: String) -> String {
            String(format: text("models.suggest_slow"), name)
        }

        public static func suggestUnused(_ name: String, _ size: String) -> String {
            String(format: text("models.suggest_unused"), name, size)
        }
    }

    public enum Library {
        public static var myFiles: String { text("library.my_files") }
        public static var folderEmpty: String { text("library.folder_empty") }
        public static var recordings: String { text("library.recordings") }
        public static var newFolder: String { text("library.new_folder") }
        public static var namePlaceholder: String { text("library.name_placeholder") }
        public static var rename: String { text("library.rename") }
        public static var move: String { text("library.move") }
        public static var merge: String { text("library.merge") }
        public static var delete: String { text("library.delete") }
        public static var moveToTrash: String { text("library.move_to_trash") }
        public static var trash: String { text("library.trash") }
        public static var select: String { text("library.select") }
        public static var more: String { text("library.more") }
        public static var search: String { text("library.search") }
        public static var searchHint: String { text("library.search_hint") }
        public static var noResults: String { text("library.no_results") }
        public static var sortBy: String { text("library.sort_by") }
        public static var sortNewest: String { text("library.sort_newest") }
        public static var sortOldest: String { text("library.sort_oldest") }
        public static var sortName: String { text("library.sort_name") }
        public static var sortLongest: String { text("library.sort_longest") }
        public static var restore: String { text("library.restore") }
        public static var emptyTrash: String { text("library.empty_trash") }
        public static var emptyTrashConfirm: String { text("library.empty_trash_confirm") }
        public static var trashEmptyTitle: String { text("library.trash_empty_title") }
        public static var trashNotice: String { text("library.trash_notice") }
        public static var importFailed: String { text("library.import_failed") }
        public static var importFailedMessage: String { text("library.import_failed_message") }

        public static func itemCount(_ count: Int) -> String {
            count == 1 ? text("library.item_count_one") : String(format: text("library.item_count"), count)
        }
    }

    public enum Common {
        public static var done: String { text("common.done") }
        public static var save: String { text("common.save") }
        public static var cancel: String { text("common.cancel") }
        public static var ok: String { text("common.ok") }
        public static var close: String { text("common.close") }
        public static var comingSoon: String { text("common.coming_soon") }
        public static var comingSoonMessage: String { text("common.coming_soon.message") }
    }

    static func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .module)
    }
}

// swiftlint:enable type_body_length
