import Foundation

public extension L10n {
    enum Tools {
        public static var section: String { text("tools.section") }
        public static var skills: String { text("tools.skills") }
        public static var templates: String { text("tools.templates") }
        public static var connectors: String { text("tools.connectors") }
    }

    enum Skills {
        public static var mine: String { text("skills.mine") }
        public static var mineEmpty: String { text("skills.mine_empty") }
        public static var official: String { text("skills.official") }
        public static var use: String { text("skills.use") }
        public static var new: String { text("skills.new") }
        public static var edit: String { text("skills.edit") }
        public static var name: String { text("skills.name") }
        public static var summary: String { text("skills.summary") }
        public static var instructions: String { text("skills.instructions") }
        public static var instructionsNote: String { text("skills.instructions_note") }

        public static func active(_ name: String) -> String {
            String(format: text("skills.active"), name)
        }

        public static func builtInName(_ id: String) -> String {
            switch id {
            case "followup": text("skills.followup.name")
            case "brief": text("skills.brief.name")
            case "objections": text("skills.objections.name")
            default: id
            }
        }

        public static func builtInSummary(_ id: String) -> String {
            switch id {
            case "followup": text("skills.followup.summary")
            case "brief": text("skills.brief.summary")
            case "objections": text("skills.objections.summary")
            default: id
            }
        }
    }

    enum Vocabulary {
        public static var title: String { text("vocabulary.title") }
        public static var hint: String { text("vocabulary.hint") }
        public static var add: String { text("vocabulary.add") }
        public static var heard: String { text("vocabulary.heard") }
        public static var written: String { text("vocabulary.written") }
        public static var appliesTo: String { text("vocabulary.applies_to") }
        public static var everywhere: String { text("vocabulary.everywhere") }
    }

    enum Connectors {
        public static var productivity: String { text("connectors.productivity") }
        public static var localWiFi: String { text("connectors.local_wifi") }
        public static var note: String { text("connectors.note") }
        public static var connect: String { text("connectors.connect") }
        public static var manage: String { text("connectors.manage") }
        public static var connected: String { text("connectors.connected") }
        public static var shares: String { text("connectors.shares") }
        public static var contentAudio: String { text("connectors.content_audio") }
        public static var contentTranscript: String { text("connectors.content_transcript") }
        public static var contentPhotos: String { text("connectors.content_photos") }
        public static var contentNotes: String { text("connectors.content_notes") }
    }
}
