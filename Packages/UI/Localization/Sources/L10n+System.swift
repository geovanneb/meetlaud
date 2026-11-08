import Foundation

public extension L10n {
    enum Widgets {
        public static var title: String { text("widgets.title") }
        public static var record: String { text("widgets.record") }
        public static var recordDescription: String { text("widgets.record_description") }
        public static var meetings: String { text("widgets.meetings") }
        public static var meetingsDescription: String { text("widgets.meetings_description") }
        public static var contentHidden: String { text("widgets.content_hidden") }
        public static var showContent: String { text("widgets.show_content") }
        public static var showContentNote: String { text("widgets.show_content_note") }
    }

    enum System {
        public static var spotlight: String { text("system.spotlight") }
        public static var spotlightNote: String { text("system.spotlight_note") }
        public static var general: String { text("system.general") }
        public static var language: String { text("system.language") }
        public static var storageTitle: String { text("system.storage_title") }
        public static var usage: String { text("system.usage") }
        public static var usageRecordings: String { text("system.usage_recordings") }
        public static var usageLibrary: String { text("system.usage_library") }
        public static var usageModels: String { text("system.usage_models") }
        public static var usageCache: String { text("system.usage_cache") }
        public static var clearCache: String { text("system.clear_cache") }
        public static var backup: String { text("system.backup") }
        public static var iosBackup: String { text("system.ios_backup") }
        public static var iosBackupNote: String { text("system.ios_backup_note") }
        public static var moveLibrary: String { text("system.move_library") }
        public static var moveLibraryNote: String { text("system.move_library_note") }
        public static var exportLibrary: String { text("system.export_library") }
        public static var importLibrary: String { text("system.import_library") }
        public static var password: String { text("system.password") }
        public static var passwordRepeat: String { text("system.password_repeat") }
        public static var includeVoicePrints: String { text("system.include_voice_prints") }
        public static var includeVoicePrintsNote: String { text("system.include_voice_prints_note") }
        public static var createFile: String { text("system.create_file") }
        public static var saveFile: String { text("system.save_file") }
        public static var chooseFile: String { text("system.choose_file") }
        public static var restore: String { text("system.restore") }
        public static var restoreWarning: String { text("system.restore_warning") }
        public static var restoreDone: String { text("system.restore_done") }
        public static var errorRecording: String { text("system.error_recording") }
        public static var errorPassword: String { text("system.error_password") }
        public static var errorDamaged: String { text("system.error_damaged") }
        public static var errorIncompatible: String { text("system.error_incompatible") }
        public static var errorOther: String { text("system.error_other") }
        public static var privacyTitle: String { text("system.privacy_title") }
        public static var security: String { text("system.security") }
        public static var appLock: String { text("system.app_lock") }
        public static var appLockNote: String { text("system.app_lock_note") }
        public static var appLockUnavailable: String { text("system.app_lock_unavailable") }
        public static var lockReason: String { text("system.lock_reason") }
        public static var lockedTitle: String { text("system.locked_title") }
        public static var unlock: String { text("system.unlock") }
        public static var promiseTitle: String { text("system.promise_title") }
        public static var promiseBody: String { text("system.promise_body") }
        public static var eraseEverything: String { text("system.erase_everything") }
        public static var eraseWarning: String { text("system.erase_warning") }
        public static var eraseWord: String { text("system.erase_word") }
        public static var notificationsTitle: String { text("system.notifications_title") }
        public static var notifyTranscript: String { text("system.notify_transcript") }
        public static var notifyEvents: String { text("system.notify_events") }
        public static var notifyNote: String { text("system.notify_note") }
        public static var transcriptReadyTitle: String { text("system.transcript_ready_title") }
        public static var eventReminderTitle: String { text("system.event_reminder_title") }
        public static var themeTitle: String { text("system.theme_title") }
        public static var themeSystem: String { text("system.theme_system") }
        public static var themeLight: String { text("system.theme_light") }
        public static var themeDark: String { text("system.theme_dark") }
        public static var about: String { text("system.about") }
        public static var version: String { text("system.version") }
        public static var license: String { text("system.license") }
        public static var aboutNote: String { text("system.about_note") }
        public static var licenses: String { text("system.licenses") }
        public static var helpCenter: String { text("system.help_center") }
        public static var helpRecordTitle: String { text("system.help_record_title") }
        public static var helpRecordBody: String { text("system.help_record_body") }
        public static var helpConsentTitle: String { text("system.help_consent_title") }
        public static var helpModelsTitle: String { text("system.help_models_title") }
        public static var helpModelsBody: String { text("system.help_models_body") }
        public static var helpAskTitle: String { text("system.help_ask_title") }
        public static var helpAskBody: String { text("system.help_ask_body") }
        public static var helpShortcutsTitle: String { text("system.help_shortcuts_title") }
        public static var helpShortcutsBody: String { text("system.help_shortcuts_body") }
        public static var helpMoveTitle: String { text("system.help_move_title") }
        public static var helpMoveBody: String { text("system.help_move_body") }
        /// The same words people saw before their first recording.
        public static var helpConsentBody: String { text("recorder.consent_message") }

        public static func passwordNote(_ length: Int) -> String {
            String(format: text("system.password_note"), length)
        }

        public static func eraseInstruction(_ word: String) -> String {
            String(format: text("system.erase_instruction"), word)
        }
    }
}
