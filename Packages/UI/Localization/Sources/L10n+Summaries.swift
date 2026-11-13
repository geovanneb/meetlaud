import Foundation

public extension L10n {
    enum Summary {
        public static var mindMap: String { text("summary.mind_map") }
        public static var title: String { text("summary.title") }
        public static var generate: String { text("summary.generate") }
        public static var choose: String { text("summary.choose") }
        public static var emptyMessage: String { text("summary.empty_message") }
        public static var needsTranscript: String { text("summary.needs_transcript") }
        public static var openTranscript: String { text("summary.open_transcript") }
        public static var add: String { text("summary.add") }
        public static var template: String { text("summary.template") }
        public static var language: String { text("summary.language") }
        public static var languageAuto: String { text("summary.language_auto") }
        public static var generateAction: String { text("summary.generate_action") }
        public static var regenerate: String { text("summary.regenerate") }
        public static var delete: String { text("summary.delete") }
        public static var deleteConfirm: String { text("summary.delete_confirm") }
        public static var share: String { text("summary.share") }
        public static var toReminders: String { text("summary.to_reminders") }
        public static var remindersAdded: String { text("summary.reminders_added") }
        public static var remindersDenied: String { text("summary.reminders_denied") }
        public static var checkThis: String { text("summary.check_this") }
        public static var emptySection: String { text("summary.empty_section") }
        public static var incomplete: String { text("summary.incomplete") }
        public static var statusQueued: String { text("summary.status_queued") }
        public static var statusReading: String { text("summary.status_reading") }
        public static var statusWriting: String { text("summary.status_writing") }
        public static var statusWaiting: String { text("summary.status_waiting") }
        public static var aiNote: String { text("summary.ai_note") }
        public static var markDone: String { text("summary.mark_done") }
        public static var markNotDone: String { text("summary.mark_not_done") }
        public static var auto: String { text("summary.auto") }
        public static var autoNote: String { text("summary.auto_note") }
        public static var profile: String { text("summary.profile") }
        public static var profileHint: String { text("summary.profile_hint") }

        public static func toRemindersConfirm(_ count: Int) -> String {
            String(format: text("summary.to_reminders_confirm"), count)
        }

        public static func listen(_ time: String) -> String {
            String(format: text("summary.listen"), time)
        }

        public static func profileNote(_ used: Int, _ limit: Int) -> String {
            String(format: text("summary.profile_note"), used, limit)
        }

        /// Built-in names are stored in English, and shown in the reader's language. People's own text stays as it is.
        public static func templateName(_ name: String) -> String {
            sectionTitle(name)
        }

        // One case per built-in name, by nature.
        // swiftlint:disable:next cyclomatic_complexity
        public static func sectionTitle(_ title: String) -> String {
            switch title {
            case "Summary": text("builtin.summary")
            case "Meeting minutes": text("builtin.minutes")
            case "Discussion summary": text("builtin.discussion")
            case "One-on-one": text("builtin.oneonone")
            case "Lecture notes": text("builtin.lecture")
            case "Interview notes": text("builtin.interview")
            case "Call notes": text("builtin.call")
            case "Key points": text("builtin.key_points")
            case "Decisions": text("builtin.decisions")
            case "Action items": text("builtin.action_items")
            case "Topics discussed": text("builtin.topics_discussed")
            case "Positions": text("builtin.positions")
            case "Agreements": text("builtin.agreements")
            case "Open questions": text("builtin.open_questions")
            case "Topics": text("builtin.topics")
            case "Feedback": text("builtin.feedback")
            case "Main ideas": text("builtin.main_ideas")
            case "Key terms": text("builtin.key_terms")
            case "To review": text("builtin.to_review")
            case "Background": text("builtin.background")
            case "Strengths": text("builtin.strengths")
            case "Concerns": text("builtin.concerns")
            case "Purpose": text("builtin.purpose")
            default: title
            }
        }
    }

    enum Templates {
        public static var mine: String { text("templates.mine") }
        public static var search: String { text("templates.search") }
        public static var new: String { text("templates.new") }
        public static var createWithAI: String { text("templates.create_ai") }
        public static var importFile: String { text("templates.import") }
        public static var importFailed: String { text("templates.import_failed") }
        public static var edit: String { text("templates.edit") }
        public static var duplicate: String { text("templates.duplicate") }
        public static var setDefault: String { text("templates.set_default") }
        public static var isDefault: String { text("templates.is_default") }
        public static var tryOn: String { text("templates.try_on") }
        public static var name: String { text("templates.name") }
        public static var categoryLabel: String { text("templates.category_label") }
        public static var instructions: String { text("templates.instructions") }
        public static var instructionsHint: String { text("templates.instructions_hint") }
        public static var sections: String { text("templates.sections") }
        public static var addSection: String { text("templates.add_section") }
        public static var sectionTitle: String { text("templates.section_title") }
        public static var saveHint: String { text("templates.save_hint") }
        public static var sectionKind: String { text("templates.section_kind") }
        public static var kindBullets: String { text("templates.kind_bullets") }
        public static var kindTasks: String { text("templates.kind_tasks") }
        public static var delete: String { text("templates.delete") }
        public static var aiPrompt: String { text("templates.ai_prompt") }
        public static var aiHint: String { text("templates.ai_hint") }
        public static var aiGenerate: String { text("templates.ai_generate") }
        public static var aiFailed: String { text("templates.ai_failed") }
        public static var needsModel: String { text("templates.needs_model") }
        public static var builtIn: String { text("templates.built_in") }
        public static var categories: String { text("templates.categories") }
        public static var seeAll: String { text("templates.see_all") }

        public static func copyName(_ name: String) -> String {
            String(format: text("templates.copy_name"), name)
        }

        public static func category(_ raw: String) -> String {
            switch raw {
            case "meeting": text("templates.cat_meeting")
            case "speech": text("templates.cat_speech")
            case "interview": text("templates.cat_interview")
            case "call": text("templates.cat_call")
            default: text("templates.cat_general")
            }
        }
    }
}
