package com.meetlaud.domain

/** The templates that come with the app. Names are English identifiers: the interface translates them. */
object BuiltInTemplates {
    const val DEFAULT_ID = "builtin.summary"

    private val keyPoints = TemplateSection("Key points")
    private val decisions = TemplateSection("Decisions")
    private val tasks = TemplateSection("Action items", SectionKind.TASKS)

    val all: List<SummaryTemplate> = listOf(
        make(
            DEFAULT_ID, "Summary", TemplateCategory.GENERAL,
            "Tell someone who missed this conversation the few things that matter: what changed and what happens next.",
            listOf(keyPoints, decisions, tasks),
        ),
        make(
            "builtin.minutes", "Meeting minutes", TemplateCategory.MEETING,
            "Write concise minutes of the main topics, the decisions, and the commitments. Skip the back and forth.",
            listOf(TemplateSection("Topics discussed"), decisions, tasks),
        ),
        make(
            "builtin.discussion", "Discussion summary", TemplateCategory.MEETING,
            "Capture the positions people took, where they agreed, and where they did not.",
            listOf(TemplateSection("Positions"), TemplateSection("Agreements"), TemplateSection("Open questions")),
        ),
        make(
            "builtin.oneonone", "One-on-one", TemplateCategory.MEETING,
            "Capture how things are going, the feedback that matters, and the few next steps people committed to.",
            listOf(TemplateSection("Topics"), TemplateSection("Feedback"), tasks),
        ),
        make(
            "builtin.lecture", "Lecture notes", TemplateCategory.SPEECH,
            "Organize the content so that a student can review it quickly.",
            listOf(TemplateSection("Main ideas"), TemplateSection("Key terms"), TemplateSection("To review")),
        ),
        make(
            "builtin.interview", "Interview notes", TemplateCategory.INTERVIEW,
            "Record what the person said about their experience, skills, and motivations.",
            listOf(TemplateSection("Background"), TemplateSection("Strengths"), TemplateSection("Concerns"), tasks),
        ),
        make(
            "builtin.call", "Call notes", TemplateCategory.CALL,
            "Record why the call happened, what was agreed, and only the follow-up people committed to.",
            listOf(TemplateSection("Purpose"), TemplateSection("Agreements"), tasks),
        ),
    )

    private fun make(id: String, name: String, category: TemplateCategory, instructions: String, sections: List<TemplateSection>) =
        SummaryTemplate(id, name, category, instructions, sections, isBuiltIn = true)
}
