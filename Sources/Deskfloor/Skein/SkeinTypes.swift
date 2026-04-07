import Foundation

// MARK: - Core Skein Types

/// One conversation session from any source.
struct Thread: Identifiable, Codable, Hashable {
    let id: UUID
    let source: Source
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var turns: [Turn]
    var status: SessionStatus
    var tags: [String]
    var topics: [String]
    var projectLinks: [UUID]
    var color: ThreadColor?

    enum Source: String, Codable, CaseIterable {
        case claudeCode, claudeWeb, chatGPT, agentSlack, codex, manual
        var label: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .claudeWeb: "Claude.ai"
            case .chatGPT: "ChatGPT"
            case .agentSlack: "AgentSlack"
            case .codex: "Codex"
            case .manual: "Manual"
            }
        }
        var icon: String {
            switch self {
            case .claudeCode: "terminal"
            case .claudeWeb: "bubble.left.and.bubble.right"
            case .chatGPT: "bubble.left"
            case .agentSlack: "person.3"
            case .codex: "doc.text"
            case .manual: "pencil"
            }
        }
    }

    var turnCount: Int { turns.count }
    var duration: TimeInterval { updatedAt.timeIntervalSince(createdAt) }
    var promptCount: Int { turns.count }

    var artifactCount: Int {
        turns.reduce(0) { $0 + $1.artifacts.count }
    }

    var toolLoopCount: Int {
        turns.reduce(0) { $0 + $1.toolLoops.count }
    }

    static func == (lhs: Thread, rhs: Thread) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum SessionStatus: String, Codable, CaseIterable, Identifiable {
    case live, completed, paused, abandoned, crashed, hypothetical, archived
    var id: String { rawValue }

    var label: String {
        switch self {
        case .live: "Live"
        case .completed: "Completed"
        case .paused: "Paused"
        case .abandoned: "Abandoned"
        case .crashed: "Crashed"
        case .hypothetical: "Hypothetical"
        case .archived: "Archived"
        }
    }

    var icon: String {
        switch self {
        case .live: "circle.fill"
        case .completed: "checkmark.circle.fill"
        case .paused: "pause.circle.fill"
        case .abandoned: "xmark.circle"
        case .crashed: "exclamationmark.triangle.fill"
        case .hypothetical: "questionmark.circle"
        case .archived: "archivebox"
        }
    }
}

/// One exchange: user prompt + assistant response + tool activity.
struct Turn: Identifiable, Codable {
    let id: UUID
    var userContent: String
    var assistantContent: String?
    var timestamp: Date?
    var toolLoops: [ToolLoop]
    var artifacts: [Artifact]
    var annotations: [Annotation]
    var isBookmarked: Bool
    var isDeadEnd: Bool
    var isBreakthrough: Bool

    init(id: UUID = UUID(), userContent: String, assistantContent: String? = nil,
         timestamp: Date? = nil, toolLoops: [ToolLoop] = [], artifacts: [Artifact] = [],
         annotations: [Annotation] = [], isBookmarked: Bool = false,
         isDeadEnd: Bool = false, isBreakthrough: Bool = false) {
        self.id = id; self.userContent = userContent; self.assistantContent = assistantContent
        self.timestamp = timestamp; self.toolLoops = toolLoops; self.artifacts = artifacts
        self.annotations = annotations; self.isBookmarked = isBookmarked
        self.isDeadEnd = isDeadEnd; self.isBreakthrough = isBreakthrough
    }

    var wordCount: Int {
        (userContent + " " + (assistantContent ?? "")).split(separator: " ").count
    }
}

/// A tool_use → tool_result cycle.
struct ToolLoop: Identifiable, Codable {
    let id: UUID
    var toolName: String
    var input: String
    var output: String
    var succeeded: Bool
    var duration: TimeInterval?

    init(id: UUID = UUID(), toolName: String, input: String, output: String,
         succeeded: Bool = true, duration: TimeInterval? = nil) {
        self.id = id; self.toolName = toolName; self.input = input
        self.output = output; self.succeeded = succeeded; self.duration = duration
    }
}

/// Extractable artifact: code, prompt, schema, command, decision, error.
struct Artifact: Identifiable, Codable {
    let id: UUID
    var kind: Kind
    var content: String
    var language: String?
    var label: String?

    enum Kind: String, Codable, CaseIterable {
        case code, prompt, schema, command, decision, error, url, document
        var icon: String {
            switch self {
            case .code: "chevron.left.forwardslash.chevron.right"
            case .prompt: "text.quote"
            case .schema: "list.bullet.rectangle"
            case .command: "terminal"
            case .decision: "arrow.triangle.branch"
            case .error: "exclamationmark.triangle"
            case .url: "link"
            case .document: "doc.text"
            }
        }
    }

    init(id: UUID = UUID(), kind: Kind, content: String,
         language: String? = nil, label: String? = nil) {
        self.id = id; self.kind = kind; self.content = content
        self.language = language; self.label = label
    }
}

/// User annotation on a turn.
struct Annotation: Identifiable, Codable {
    let id: UUID
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id; self.text = text; self.createdAt = createdAt
    }
}

/// Connection between turns in different threads.
struct Splice: Identifiable, Codable {
    let id: UUID
    var fromThread: UUID
    var fromTurn: UUID
    var toThread: UUID
    var toTurn: UUID
    var label: String

    init(id: UUID = UUID(), fromThread: UUID, fromTurn: UUID,
         toThread: UUID, toTurn: UUID, label: String) {
        self.id = id; self.fromThread = fromThread; self.fromTurn = fromTurn
        self.toThread = toThread; self.toTurn = toTurn; self.label = label
    }
}

/// A piece pulled from a thread into the excerpt board.
struct Excerpt: Identifiable, Codable {
    let id: UUID
    var sourceThread: UUID
    var sourceTurn: UUID
    var content: String
    var kind: Artifact.Kind
    var column: Column
    var note: String?

    enum Column: String, Codable, CaseIterable {
        case prompts, decisions, deadEnds, artifacts, context
        var label: String {
            switch self {
            case .prompts: "Prompts"
            case .decisions: "Decisions"
            case .deadEnds: "Dead Ends"
            case .artifacts: "Artifacts"
            case .context: "Context"
            }
        }
    }

    init(id: UUID = UUID(), sourceThread: UUID, sourceTurn: UUID,
         content: String, kind: Artifact.Kind, column: Column, note: String? = nil) {
        self.id = id; self.sourceThread = sourceThread; self.sourceTurn = sourceTurn
        self.content = content; self.kind = kind; self.column = column; self.note = note
    }
}

/// A new context assembled from excerpts.
struct Composition: Identifiable, Codable {
    let id: UUID
    var title: String
    var pieces: [Piece]
    var freeText: String
    var createdAt: Date
    var dispatched: Bool

    struct Piece: Identifiable, Codable {
        let id: UUID
        var excerptID: UUID?
        var content: String
        var label: String

        init(id: UUID = UUID(), excerptID: UUID? = nil, content: String, label: String) {
            self.id = id; self.excerptID = excerptID; self.content = content; self.label = label
        }
    }

    init(id: UUID = UUID(), title: String = "Untitled", pieces: [Piece] = [],
         freeText: String = "", createdAt: Date = Date(), dispatched: Bool = false) {
        self.id = id; self.title = title; self.pieces = pieces
        self.freeText = freeText; self.createdAt = createdAt; self.dispatched = dispatched
    }

    var fullText: String {
        (pieces.map(\.content) + [freeText])
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    var estimatedTokens: Int { fullText.count / 4 }
}

enum ThreadColor: String, Codable, CaseIterable {
    case red, orange, amber, green, teal, blue, indigo, purple, pink, gray

}
