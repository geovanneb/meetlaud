import Foundation

/// A prompt recipe: instructions that shape how the chat answers. Skills change the form of an answer and never its
/// sources, so the rule that every statement comes from a transcript still holds.
public struct Skill: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    public var summary: String
    public var instructions: String
    public var isBuiltIn: Bool

    public static let instructionsLimit = 1500

    public init(
        id: String = UUID().uuidString,
        name: String,
        summary: String,
        instructions: String,
        isBuiltIn: Bool = false,
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.instructions = instructions
        self.isBuiltIn = isBuiltIn
    }

    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The skills that come with the app. Names and summaries are identifiers: the interface translates them.
public enum BuiltInSkills {
    public static let all: [Skill] = [
        Skill(
            id: "builtin.followup", name: "followup", summary: "followup",
            instructions: "Write a short follow-up email: a thank you, the decisions, and who does what next.",
            isBuiltIn: true,
        ),
        Skill(
            id: "builtin.brief", name: "brief", summary: "brief",
            instructions: "Answer as a brief for an executive: three lines at most, the outcome first.",
            isBuiltIn: true,
        ),
        Skill(
            id: "builtin.objections", name: "objections", summary: "objections",
            instructions: "List the objections and concerns people raised, and how each one was answered.",
            isBuiltIn: true,
        ),
    ]
}

/// A skill as a file. Files come from other people, so nothing in them is trusted: a file can never replace a skill
/// or pass for a built-in one.
public enum SkillCodec {
    private struct File: Codable {
        var name: String
        var summary: String?
        var instructions: String
    }

    public enum Failure: Error {
        case invalid
    }

    public static func decode(_ data: Data) throws -> Skill {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.name.count <= 80, file.instructions.count <= Skill.instructionsLimit else { throw Failure.invalid }
        let skill = Skill(name: file.name, summary: file.summary ?? "", instructions: file.instructions)
        guard skill.isValid else { throw Failure.invalid }
        return skill
    }

    public static func encode(_ skill: Skill) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(File(name: skill.name, summary: skill.summary, instructions: skill.instructions))
    }
}

/// Whether meeting titles can appear in iOS search. Off until the person turns it on, and turning it off clears them.
public enum SpotlightPreferences {
    public static let key = "privacy.spotlight"
}

/// The system's search index, on this device. Only titles and dates go in.
public protocol SystemSearchIndex: Sendable {
    func index(_ recordings: [Recording]) async
    func removeAll() async
}
