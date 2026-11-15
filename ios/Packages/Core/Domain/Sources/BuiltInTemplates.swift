import Foundation

/// The templates that come with the app. Names are English identifiers: the interface translates them.
public enum BuiltInTemplates {
    public static let defaultID = "builtin.summary"

    private static let keyPoints = TemplateSection(title: "Key points")
    private static let decisions = TemplateSection(title: "Decisions")
    private static let tasks = TemplateSection(title: "Action items", kind: .tasks)

    public static let all: [SummaryTemplate] = [
        make(
            defaultID, "Summary", .general,
            "Tell someone who missed this conversation the few things that matter: what changed and what happens next.",
            [keyPoints, decisions, tasks],
        ),
        make(
            "builtin.minutes", "Meeting minutes", .meeting,
            "Write concise minutes of the main topics, the decisions, and the commitments. Skip the back and forth.",
            [TemplateSection(title: "Topics discussed"), decisions, tasks],
        ),
        make(
            "builtin.discussion", "Discussion summary", .meeting,
            "Capture the positions people took, where they agreed, and where they did not.",
            [
                TemplateSection(title: "Positions"),
                TemplateSection(title: "Agreements"),
                TemplateSection(title: "Open questions"),
            ],
        ),
        make(
            "builtin.oneonone", "One-on-one", .meeting,
            "Capture how things are going, the feedback that matters, and the few next steps people committed to.",
            [TemplateSection(title: "Topics"), TemplateSection(title: "Feedback"), tasks],
        ),
        make(
            "builtin.lecture", "Lecture notes", .speech,
            "Organize the content so that a student can review it quickly.",
            [
                TemplateSection(title: "Main ideas"),
                TemplateSection(title: "Key terms"),
                TemplateSection(title: "To review"),
            ],
        ),
        make(
            "builtin.interview", "Interview notes", .interview,
            "Record what the person said about their experience, skills, and motivations.",
            [
                TemplateSection(title: "Background"),
                TemplateSection(title: "Strengths"),
                TemplateSection(title: "Concerns"),
                tasks,
            ],
        ),
        make(
            "builtin.call", "Call notes", .call,
            "Record why the call happened, what was agreed, and only the follow-up people committed to.",
            [TemplateSection(title: "Purpose"), TemplateSection(title: "Agreements"), tasks],
        ),
    ]

    private static func make(
        _ id: String,
        _ name: String,
        _ category: TemplateCategory,
        _ instructions: String,
        _ sections: [TemplateSection],
    ) -> SummaryTemplate {
        SummaryTemplate(
            id: id, name: name, category: category, instructions: instructions, sections: sections, isBuiltIn: true,
        )
    }
}
