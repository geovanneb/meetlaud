import Foundation

public extension L10n {
    enum Ask {
        public static var history: String { text("ask.history") }
        public static var newChat: String { text("ask.new_chat") }
        public static var placeholder: String { text("ask.placeholder") }
        public static var aboutMeeting: String { text("ask.about_meeting") }
        public static var aboutFolder: String { text("ask.about_folder") }
        public static var emptyTitle: String { text("ask.empty_title") }
        public static var emptyMessage: String { text("ask.empty_message") }
        public static var scope: String { text("ask.scope") }
        public static var scopeLibrary: String { text("ask.scope_library") }
        public static var scopeMeeting: String { text("ask.scope_meeting") }
        public static var send: String { text("ask.send") }
        public static var stop: String { text("ask.stop") }
        public static var statusWaiting: String { text("ask.status_waiting") }
        public static var statusSearching: String { text("ask.status_searching") }
        public static var statusWriting: String { text("ask.status_writing") }
        public static var noBasis: String { text("ask.no_basis") }
        public static var stopped: String { text("ask.stopped") }
        public static var failed: String { text("ask.failed") }
        public static var needsModel: String { text("ask.needs_model") }
        public static var getModel: String { text("ask.get_model") }
        public static var delete: String { text("ask.delete") }
        public static var suggestDecisions: String { text("ask.suggest_decisions") }
        public static var suggestTasks: String { text("ask.suggest_tasks") }
        public static var suggestRisks: String { text("ask.suggest_risks") }
        public static var memory: String { text("ask.memory") }
        public static var memoryHint: String { text("ask.memory_hint") }
        public static var memoryAdd: String { text("ask.memory_add") }
        public static var promptBar: String { text("ask.prompt_bar") }
        public static var promptFocus: String { text("ask.prompt_focus") }
        public static var promptNew: String { text("ask.prompt_new") }

        public static func remembered(_ fact: String) -> String {
            String(format: text("ask.remembered"), fact)
        }

        public static func openSource(_ title: String, _ time: String) -> String {
            String(format: text("ask.open_source"), title, time)
        }

        public static func indexing(_ done: Int, _ total: Int) -> String {
            String(format: text("ask.indexing"), done, total)
        }
    }
}
