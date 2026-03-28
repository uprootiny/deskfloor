# Skein — Thread Weaving Interface for LLM Session Archaeology

## Metaphor

A **skein** is a loosely wound bundle of yarn — threads intertwined but distinct,
each traceable, each pullable. An LLM session is a thread. A tool-use loop is a
twist in the thread. A dead end is a snipped end. A breakthrough is where threads
merge.

The Skein view doesn't just show conversations — it shows the **topology of development**
as threads that you can:

- **Pull** — resume an abandoned thread with its full context
- **Splice** — join two threads that discovered the same thing independently
- **Unravel** — inspect a thread turn by turn, extracting reusable pieces
- **Wind** — compose a new thread from pieces of old ones
- **Dye** — tag threads by project, topic, mood, outcome

## Architecture

```
Skein (the whole tapestry)
├── Thread (one conversation/session)
│   ├── Strand (a contiguous sequence of user↔assistant turns)
│   │   ├── Turn (one user prompt + assistant response)
│   │   │   ├── Artifacts (code, schemas, commands, decisions)
│   │   │   ├── Tool loops (tool_use → tool_result sequences)
│   │   │   └── Annotations (user bookmarks, dead-end marks, "this worked" flags)
│   │   └── ...more turns
│   └── ...more strands (branches within a conversation)
├── Splice (explicit connection between turns in different threads)
├── Excerpt (a pulled-out piece, living in the excerpt board)
└── Composition (a new context assembled from excerpts)
```

## Data Model

### Core Types

```swift
/// The entire collection of conversation threads.
@Observable
final class Skein {
    var threads: [Thread] = []
    var splices: [Splice] = []
    var excerpts: [Excerpt] = []
    var compositions: [Composition] = []
}

/// One conversation session from any source.
struct Thread: Identifiable, Codable {
    let id: UUID
    let source: Source
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var turns: [Turn]
    var status: Status
    var tags: [String]
    var topics: [String]          // NLP-extracted
    var projectLinks: [UUID]      // linked Deskfloor projects
    var color: ThreadColor?       // user-assigned visual color

    enum Source: String, Codable {
        case claudeCode     // local ~/.claude JSONL
        case claudeWeb      // claude.ai data export
        case chatGPT        // OpenAI data export
        case agentSlack     // AgentSlack message feed
        case codex           // OpenAI Codex / other
        case manual          // user-created
    }

    enum Status: String, Codable, CaseIterable {
        case live            // currently in progress
        case completed       // reached its goal
        case paused          // intentionally set down
        case abandoned       // stopped without resolution
        case crashed         // hit a wall / error
        case hypothetical    // planned, not started
        case archived        // done, not interesting
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
    var isDeadEnd: Bool          // "this didn't work"
    var isBreakthrough: Bool     // "this was the key insight"
}

/// A tool_use → tool_result cycle within a turn.
struct ToolLoop: Identifiable, Codable {
    let id: UUID
    var toolName: String         // Bash, Read, Edit, Agent, etc.
    var input: String            // truncated tool input
    var output: String           // truncated tool output
    var succeeded: Bool
    var duration: TimeInterval?
}

/// Something extractable: code, prompt, schema, decision, error.
struct Artifact: Identifiable, Codable {
    let id: UUID
    var kind: Kind
    var content: String
    var language: String?
    var label: String?           // user-given name

    enum Kind: String, Codable, CaseIterable {
        case code, prompt, schema, command, decision, error, url, document
    }
}

/// User annotation on a turn.
struct Annotation: Identifiable, Codable {
    let id: UUID
    var text: String
    var createdAt: Date
}

/// A connection between turns in different threads.
struct Splice: Identifiable, Codable {
    let id: UUID
    var fromThread: UUID
    var fromTurn: UUID
    var toThread: UUID
    var toTurn: UUID
    var label: String            // "same approach", "this led to", "contradicts"
}

/// A piece pulled out of a thread into the excerpt board.
struct Excerpt: Identifiable, Codable {
    let id: UUID
    var sourceThread: UUID
    var sourceTurn: UUID
    var content: String
    var kind: Artifact.Kind
    var column: ExcerptColumn
    var note: String?

    enum ExcerptColumn: String, Codable, CaseIterable {
        case prompts, decisions, deadEnds, artifacts, context
    }
}

/// A new context assembled from excerpts, ready to dispatch.
struct Composition: Identifiable, Codable {
    let id: UUID
    var title: String
    var pieces: [CompositionPiece]
    var freeText: String         // user's added prompt text
    var createdAt: Date
    var dispatched: Bool         // has this been used?

    struct CompositionPiece: Identifiable, Codable {
        let id: UUID
        var excerptID: UUID?     // from an excerpt, or...
        var freeContent: String? // manually typed
        var label: String
    }

    var fullText: String {
        let parts = pieces.map { piece in
            if let content = piece.freeContent { return content }
            return "[\(piece.label)]"
        }
        return (parts + [freeText]).joined(separator: "\n\n")
    }

    var estimatedTokens: Int {
        fullText.count / 4 // rough approximation
    }
}

/// Visual color for a thread.
enum ThreadColor: String, Codable, CaseIterable {
    case red, orange, amber, green, teal, blue, indigo, purple, pink, gray
}
```

### Persistence

SQLite via raw queries (no ORM). Tables:
- `threads` — core thread metadata
- `turns` — all turns, FK to thread
- `tool_loops` — FK to turn
- `artifacts` — FK to turn
- `annotations` — FK to turn
- `splices` — FK to two turns
- `excerpts` — FK to turn
- `compositions` — FK chain to excerpts

Why SQLite not JSON: 281 prompts × 79 conversations × avg 50 turns = ~15K turns.
JSON would be 50MB+. SQLite handles this with indexed queries in milliseconds.

## Views

### 1. Skein View (Cmd+5) — The Tapestry

A 2D canvas showing threads as horizontal lines on a time axis:

```
                    Mar 26      Mar 27      Mar 28
                    ──────────────────────────────────
    Claude Code  ─  ═══════╤════╤═══════╤════════════════
                           │    │       │
    Claude Code  ─         │    ════════╧══════════
                           │         ↑ splice
    ChatGPT      ─         ═══════════
                               ↓
    AgentSlack   ─  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
                    (continuous, low-intensity)

    Subagents    ─  ·· ·· ··    ···· ··      ···· ···· ····
                    (short bursts)
```

- Thick lines = active threads. Thin = paused. Dashed = abandoned. Dotted = subagents.
- Vertical connections = splices between threads.
- Click a thread → opens Session Inspector.
- Drag to select a time range → shows all turns in that range across all threads.
- Zoom: scroll to zoom time axis. Pinch to zoom vertically.
- Color: by project link, by source, or by user-assigned thread color.

### 2. Loom View (Cmd+6) — The Excerpt Board

Kanban columns for extracted pieces:

| Prompts | Decisions | Dead Ends | Artifacts | Context |
| (reusable prompts) | (key choices) | (what failed) | (code/schemas) | (background) |

- Drag from Session Inspector into a column.
- Drag between columns to reclassify.
- Drag from any column into the Composer.
- Each card shows: source thread title, timestamp, content preview.
- Filter by project, source, or tag.

### 3. Shuttle View (Cmd+7) — The Context Composer

A vertical scratchpad for weaving a new context:

- Drop zone at top: drag excerpts, prompts, or artifacts here.
- Each dropped piece becomes an editable card.
- Reorder cards by dragging.
- Free text area at bottom for your prompt.
- Live token count (chars/4).
- Actions: [Copy All] [Open in Claude Code] [Save as Composition] [Save as Prompt]

### 4. Session Inspector (detail overlay)

Opens when clicking a thread in the Skein View:

- Scrollable turn-by-turn view.
- Each turn: user content (highlighted), assistant content (collapsible).
- Tool loops shown as indented sub-turns with icons (Bash→terminal, Read→file, etc.).
- Annotations inline.
- Bookmarks (⭐), dead-end marks (✕), breakthrough marks (✓) as toggle buttons.
- Right sidebar: extracted artifacts, topics, linked projects.
- Actions per turn: [→ to Loom] [→ to Shuttle] [↻ Rerun] [📋 Copy]

## Importers

### ClaudeCodeImporter
- Reads ~/.claude/history.jsonl for prompts
- Reads ~/.claude/projects/*/*.jsonl for full conversations
- Reads ~/.claude/projects/*/subagents/*.jsonl for subagent threads
- Each JSONL file = one Thread
- Each message pair (user + next assistant) = one Turn
- Tool use blocks within assistant messages = ToolLoops

### ChatGPTImporter
- Reads conversations.json from data export zip
- Each conversation = one Thread
- Traverses mapping tree (parent→children) to reconstruct linear turn order
- content.parts[0] = message text

### ClaudeWebImporter
- Reads conversations from claude.ai data export
- Each conversation = one Thread
- chat_messages array = turns (pair human + assistant)

### AgentSlackImporter
- Fetches from http://173.212.203.211:9400/history/{channel}
- Each channel = one Thread (continuous)
- Each message = one Turn (agent = assistant, human = user)

## UX Principles for the Skein

1. **Threads are first-class objects.** Not buried in files — visible, taggable, linkable.
2. **Status matters.** Abandoned ≠ completed ≠ crashed. Each gets distinct visual treatment.
3. **Excerpts are the currency.** Pull pieces out, recombine, dispatch. The loom is where value accumulates.
4. **Splices are memory.** When two threads discover the same thing, splice them. Next time you're in that area, you see the connection.
5. **Compositions are actions.** Not just notes — they're ready-to-dispatch prompts with assembled context.
6. **Time is the backbone.** Everything plotted on time. Sessions are lanes. Zoom in to see turns, zoom out to see arcs.
