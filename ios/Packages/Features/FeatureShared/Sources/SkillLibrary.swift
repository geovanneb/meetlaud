import Domain
import Foundation
import Localization
import Observation

/// The person's own skills, on this device only. Tools edits them and Ask uses them.
@MainActor
@Observable
public final class SkillLibrary {
    public private(set) var mine: [Skill]

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "tools.skills"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mine = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([Skill].self, from: $0) } ?? []
    }

    public var all: [Skill] {
        mine + BuiltInSkills.all
    }

    public func skill(id: String) -> Skill? {
        all.first { $0.id == id }
    }

    public func save(_ skill: Skill) {
        guard skill.isValid, !skill.isBuiltIn else { return }
        if let index = mine.firstIndex(where: { $0.id == skill.id }) {
            mine[index] = skill
        } else {
            mine.insert(skill, at: 0)
        }
        persist()
    }

    public func delete(_ skill: Skill) {
        mine.removeAll { $0.id == skill.id }
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(mine), forKey: Self.key)
    }
}

public extension Skill {
    var displayName: String {
        isBuiltIn ? L10n.Skills.builtInName(name) : name
    }

    var displaySummary: String {
        isBuiltIn ? L10n.Skills.builtInSummary(summary) : summary
    }
}
