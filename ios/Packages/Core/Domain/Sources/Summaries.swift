import Foundation

public enum SectionKind: String, Codable, Sendable {
    case bullets, tasks
}

public struct TemplateSection: Hashable, Codable, Sendable {
    public var title: String
    public var kind: SectionKind

    public init(title: String, kind: SectionKind = .bullets) {
        self.title = title
        self.kind = kind
    }
}

public enum TemplateCategory: String, CaseIterable, Codable, Sendable {
    case general, meeting, speech, interview, call
}

/// How a summary is organized. Also the format of a template file, so that people can share them.
public struct SummaryTemplate: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public var category: TemplateCategory
    public var instructions: String
    public var sections: [TemplateSection]
    public var isBuiltIn: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        category: TemplateCategory,
        instructions: String,
        sections: [TemplateSection],
        isBuiltIn: Bool = false,
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.instructions = instructions
        self.sections = sections
        self.isBuiltIn = isBuiltIn
    }
}

/// One statement in a summary. `sourceTime` is the proof: where the audio says it.
public struct SummaryItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var text: String
    public var sourceTime: TimeInterval?
    /// Tasks only. Stored as written, or as a speaker token so that renaming reaches it.
    public var owner: String?
    public var due: String?
    public var isDone: Bool
    /// The model's claim could not be tied to the transcript, so a person should check it.
    public var needsReview: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        sourceTime: TimeInterval? = nil,
        owner: String? = nil,
        due: String? = nil,
        isDone: Bool = false,
        needsReview: Bool = false,
    ) {
        self.id = id
        self.text = text
        self.sourceTime = sourceTime
        self.owner = owner
        self.due = due
        self.isDone = isDone
        self.needsReview = needsReview
    }
}

public struct SummarySection: Hashable, Codable, Sendable {
    public var title: String
    public var kind: SectionKind
    public var items: [SummaryItem]

    public init(title: String, kind: SectionKind, items: [SummaryItem]) {
        self.title = title
        self.kind = kind
        self.items = items
    }
}

public struct Summary: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let recordingID: RecordingID
    public var templateName: String
    public var modelID: String
    public var language: String?
    public var sections: [SummarySection]
    public var isComplete: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        recordingID: RecordingID,
        templateName: String,
        modelID: String,
        language: String?,
        sections: [SummarySection] = [],
        isComplete: Bool = false,
        createdAt: Date,
    ) {
        self.id = id
        self.recordingID = recordingID
        self.templateName = templateName
        self.modelID = modelID
        self.language = language
        self.sections = sections
        self.isComplete = isComplete
        self.createdAt = createdAt
    }
}

/// Work that survives the app closing, or iOS taking the GPU away.
public struct SummaryJob: Codable, Sendable, Equatable {
    public let summaryID: UUID
    public let recordingID: RecordingID
    public let template: SummaryTemplate
    public let modelID: String
    public let language: String?
    public var nextChunk: Int
    public var notes: [String]
    public var nextSection: Int
    /// Runs that never reached an end. A job that keeps killing the app has to stop being retried.
    public var attempts: Int

    public init(
        summaryID: UUID,
        recordingID: RecordingID,
        template: SummaryTemplate,
        modelID: String,
        language: String?,
        nextChunk: Int = 0,
        notes: [String] = [],
        nextSection: Int = 0,
        attempts: Int = 0,
    ) {
        self.summaryID = summaryID
        self.recordingID = recordingID
        self.template = template
        self.modelID = modelID
        self.language = language
        self.nextChunk = nextChunk
        self.notes = notes
        self.nextSection = nextSection
        self.attempts = attempts
    }
}

public protocol SummaryStore: Sendable {
    func summaries(for id: RecordingID) async throws -> [Summary]
    func save(_ summary: Summary) async throws
    /// One transaction, so that a section can never be saved without its checkpoint, and written twice on resume.
    func save(_ summary: Summary, job: SummaryJob) async throws
    /// Marks it complete and removes its job, in one transaction.
    func complete(_ summary: Summary) async throws
    func deleteSummary(_ id: UUID) async throws

    func summaryJobs() async throws -> [SummaryJob]
    func save(_ job: SummaryJob) async throws
    func deleteSummaryJob(_ summaryID: UUID) async throws

    func userTemplates() async throws -> [SummaryTemplate]
    func save(_ template: SummaryTemplate) async throws
    func deleteTemplate(_ id: String) async throws
}

/// Sends tasks to the Reminders app, always from a person's explicit action.
public protocol RemindersProvider: Sendable {
    /// Asks for access the first time. Throws `RemindersError.denied` without it.
    func add(title: String, notes: String?) async throws
}

public enum SummaryError: Error, Equatable {
    case nothingToSummarize
}

public enum RemindersError: Error, Equatable {
    case denied
}

public struct SummaryProgress: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        case queued, reading, writing, waiting
    }

    public let phase: Phase
    public let fraction: Double
    /// What the model has written so far in the current section.
    public let partial: String?

    public init(phase: Phase, fraction: Double, partial: String? = nil) {
        self.phase = phase
        self.fraction = fraction
        self.partial = partial
    }
}

/// A summary as a tree: the meeting, its sections, and what each one says. Built from the summary itself, so that it
/// needs no model and every leaf keeps its link to the audio.
public struct MindMapNode: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let time: TimeInterval?
    public let children: [MindMapNode]

    public init(id: String, title: String, time: TimeInterval? = nil, children: [MindMapNode] = []) {
        self.id = id
        self.title = title
        self.time = time
        self.children = children
    }

    /// Empty sections are left out: a branch with nothing on it says nothing.
    public static func tree(title: String, summary: Summary) -> MindMapNode {
        let branches = summary.sections.enumerated().compactMap { index, section -> MindMapNode? in
            guard !section.items.isEmpty else { return nil }
            return MindMapNode(
                id: "section-\(index)",
                title: section.title,
                children: section.items.map {
                    MindMapNode(id: $0.id.uuidString, title: $0.text, time: $0.sourceTime)
                },
            )
        }
        return MindMapNode(id: "root", title: title, children: branches)
    }
}
