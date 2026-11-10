@testable import Domain
import Foundation
import Testing

struct SkillTests {
    @Test func `a skill shapes the answer after the rule on sources`() {
        let request = AskPrompts.answer(
            question: "What now?", excerpts: [], history: [], memories: [], profile: nil, skill: "Answer as a poem.",
        )
        let rule = request.system.range(of: "End each sentence with the number")
        let shape = request.system.range(of: "Shape your answer this way: Answer as a poem.")
        #expect(rule != nil && shape != nil)
        if let rule, let shape {
            #expect(rule.lowerBound < shape.lowerBound)
        }
    }

    @Test func `with no skill the prompt says nothing about shape`() {
        let request = AskPrompts.answer(question: "Q", excerpts: [], history: [], memories: [], profile: nil)
        #expect(!request.system.contains("Shape your answer"))
    }

    @Test func `a skill needs a name and instructions`() {
        #expect(!Skill(name: " ", summary: "", instructions: "x").isValid)
        #expect(!Skill(name: "x", summary: "", instructions: "\n").isValid)
        #expect(Skill(name: "x", summary: "", instructions: "y").isValid)
    }

    @Test func `built-in skills have unique ids and instructions`() {
        #expect(Set(BuiltInSkills.all.map(\.id)).count == BuiltInSkills.all.count)
        #expect(BuiltInSkills.all.allSatisfy { $0.isValid && $0.isBuiltIn })
    }
}

struct SkillCodecTests {
    @Test func `a file comes back as a new skill of the person's own`() throws {
        let skill = Skill(name: "Brief", summary: "Short", instructions: "Be short.", isBuiltIn: true)
        let copy = try SkillCodec.decode(SkillCodec.encode(skill))
        #expect(copy.name == "Brief")
        #expect(copy.instructions == "Be short.")
        #expect(!copy.isBuiltIn, "A file must never pass for a built-in")
        #expect(copy.id != skill.id, "A file must never replace an existing skill")
    }

    @Test func `a file with no instructions or far too long is refused`() {
        #expect(throws: (any Error).self) {
            try SkillCodec.decode(Data(#"{"name":"A","instructions":" "}"#.utf8))
        }
        let long = String(repeating: "x", count: Skill.instructionsLimit + 1)
        #expect(throws: (any Error).self) {
            try SkillCodec.decode(Data(#"{"name":"A","instructions":"\#(long)"}"#.utf8))
        }
    }

    @Test func `something that is not a skill is refused`() {
        #expect(throws: (any Error).self) { try SkillCodec.decode(Data("nope".utf8)) }
    }
}
