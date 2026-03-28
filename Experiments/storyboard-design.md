# Conversation Storyboard — UX Design

## The Problem

You have hundreds of conversations across multiple AI systems:
- Claude Code sessions (79 local JSONL files, 281 prompts)
- Claude.ai web conversations (data takeout → conversations.json)
- ChatGPT conversations (data takeout → conversations.json)
- AgentSlack agent messages (130+ on hyle)
- Subagent transcripts (22 JSONL files)

Each conversation is a development session — a sequence of decisions, experiments,
dead ends, breakthroughs, and artifacts. But they're all linear, isolated, and unstructured.

You can't:
- See which conversations touched the same project
- Find the prompt that worked after 3 failed attempts
- Reconstruct the development arc of a feature across sessions
- Pick up abandoned sessions with their full context
- Compose new contexts from excerpts of old ones

## The Insight

Conversations are not documents — they're **development traces**. Each one is a path
through a decision space. The storyboard lets you:

1. **See the paths** — timeline of sessions, colored by project/topic
2. **Extract the nodes** — individual prompts, decisions, artifacts
3. **Recombine** — drag nodes from different sessions into a new composition
4. **Replay** — take an extracted prompt and run it again with fresh context
5. **Tag the dead ends** — mark "this approach failed because X" so you don't repeat it

## Data Model

```swift
struct ConversationSource: Identifiable, Codable {
    let id: UUID
    let provider: Provider   // .claudeCode, .claudeWeb, .chatGPT, .agentSlack
    let importedAt: Date
    let filePath: String?    // original file
    var conversations: [Conversation]

    enum Provider: String, Codable {
        case claudeCode, claudeWeb, chatGPT, agentSlack
    }
}

struct Conversation: Identifiable, Codable {
    let id: UUID
    let sourceProvider: ConversationSource.Provider
    let title: String        // first prompt or ChatGPT title
    let createdAt: Date
    let updatedAt: Date
    var messages: [Message]
    var tags: [String]       // user-assigned
    var topics: [String]     // NLP-extracted
    var projectLinks: [UUID] // linked to Deskfloor projects
    var status: SessionStatus

    enum SessionStatus: String, Codable {
        case active          // currently productive
        case paused          // put down intentionally
        case abandoned       // stopped without resolution
        case completed       // reached its goal
        case crashed         // hit an error/dead-end
        case hypothetical    // planned but never started
        case prospective     // template for future use
    }
}

struct Message: Identifiable, Codable {
    let id: UUID
    let role: Role           // .user, .assistant, .system, .tool
    let content: String
    let timestamp: Date?
    var isBookmarked: Bool   // user flagged as important
    var isPromptCandidate: Bool  // NLP detected as reusable
    var note: String?        // user annotation
    var extractedArtifacts: [Artifact]

    enum Role: String, Codable { case user, assistant, system, tool }
}

struct Artifact: Identifiable, Codable {
    let id: UUID
    let kind: Kind
    let content: String
    let language: String?    // for code

    enum Kind: String, Codable {
        case code, schema, prompt, command, url, decision, error
    }
}
```

## View Designs

### 1. Session Timeline (new view mode: Cmd+5)

A horizontal timeline showing all conversation sessions as swim lanes:

```
         Mar 26          Mar 27          Mar 28
         ─────────────────────────────────────────
Claude   ████████████    ████████        ████████████████
Code     bootstrap       discovery       deskfloor

ChatGPT                  ██████
                         coggy research

AgentSlack ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
           continuous agent chatter

Subagents    ██ ██ ██        ████  ██      ████ ████ ████
             build   probe   fleet  ray    iterm rain nlp
```

Each bar is clickable → expands to show the conversation's messages.
Color-coded by project link (if linked) or topic (if auto-detected).
Sessions can be dragged to reorder, grouped, or linked.

### 2. Excerpt Board (new view mode: Cmd+6)

Like the project board, but for conversation excerpts:

```
┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│ Prompts      │ │ Decisions    │ │ Dead Ends    │ │ Artifacts    │
│              │ │              │ │              │ │              │
│ "review this │ │ "use Swift   │ │ "tried exec  │ │ PLAN.md      │
│  code for    │ │  not Python" │ │  in Raycast  │ │ DISCOVERY.md │
│  arch..."    │ │              │ │  — sandboxed" │ │ serve.py fix │
│              │ │ "NSPanel not │ │              │ │              │
│ "debug this  │ │  Window for  │ │ "iterm2://   │ │ nlp-engine   │
│  system..."  │ │  launcher"   │ │  URL scheme  │ │  harvest     │
│              │ │              │ │  runs silent" │ │              │
└─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘
```

Drag excerpts between columns.
"Prompts" column items can be Cmd+Enter'd to paste into clipboard.
"Dead Ends" items serve as warnings when similar approaches are attempted.

### 3. Context Composer (new panel, Cmd+7)

A scratchpad for assembling new prompts from old conversation pieces:

```
┌────────────────────────────────────────────────────────┐
│ Context Composer                              [Export]  │
├────────────────────────────────────────────────────────┤
│                                                        │
│ ┌──────────────────────────────────────────────────┐  │
│ │ From: bootstrap session (Mar 26)                  │  │
│ │ "we have 168 repos, classified as MUST CLONE..."  │  │
│ └──────────────────────────────────────────────────┘  │
│                                                        │
│ ┌──────────────────────────────────────────────────┐  │
│ │ From: fleet digest (Mar 27)                       │  │
│ │ "hyle: load 1.0, disk 75%, 8 claude instances..." │  │
│ └──────────────────────────────────────────────────┘  │
│                                                        │
│ ┌──────────────────────────────────────────────────┐  │
│ │ Your prompt:                                      │  │
│ │ "Given this context, what should we prioritize    │  │
│ │  for the next session? Consider both local builds │  │
│ │  and server-side fixes."                          │  │
│ └──────────────────────────────────────────────────┘  │
│                                                        │
│ [Add from clipboard] [Add from session] [Clear]        │
│                                                        │
│ Combined context: 847 tokens                           │
│ [Copy All] [Open in Claude Code] [Save as Prompt]      │
└────────────────────────────────────────────────────────┘
```

Drag excerpts from the Session Timeline or Excerpt Board into the Composer.
Export copies the assembled context to clipboard or opens a new Claude Code session.

### 4. Session Inspector (detail view, opens from timeline)

Shows a single conversation with annotations:

```
┌─────────────────────────────────────────────────────────┐
│ Session: bootstrap & discovery  │ Mar 26  │ ◉ completed │
│ Topics: setup, nix, github, fleet  │ Projects: 3 linked │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ YOU 14:22                                               │
│ "this is my fresh mac this is my iterm..."              │
│ [☆ bookmark] [→ to composer] [↻ rerun]                  │
│                                                         │
│ CLAUDE 14:22                                            │
│ "Welcome! Let me set up your environment..."            │
│ ├── artifact: .zshrc changes (code/shell)               │
│ ├── artifact: settings.json (code/json)                 │
│ └── decision: use nix over brew                         │
│                                                         │
│ YOU 14:30                                               │
│ "i would rather not use brew..."                   ★    │
│ [this became a project constraint — saved to memory]    │
│                                                         │
│ ... 276 more messages ...                               │
│                                                         │
│ [Collapse assistant messages] [Show only bookmarked]    │
│ [Extract all prompts] [Extract all artifacts]           │
└─────────────────────────────────────────────────────────┘
```

## Ingest Formats

### ChatGPT Data Export
```json
// conversations.json — array of conversations
[{
  "title": "Project Planning",
  "create_time": 1679012345.678,
  "update_time": 1679023456.789,
  "mapping": {
    "msg-id-1": {
      "message": {
        "author": {"role": "user"},
        "content": {"parts": ["the actual message text"]},
        "create_time": 1679012345.678
      },
      "parent": "msg-id-0",
      "children": ["msg-id-2"]
    }
  }
}]
```

### Claude.ai Data Export
```json
// conversations.json or similar
[{
  "uuid": "...",
  "name": "Session title",
  "created_at": "2026-03-26T...",
  "updated_at": "2026-03-28T...",
  "chat_messages": [
    {"uuid": "...", "sender": "human", "text": "...", "created_at": "..."},
    {"uuid": "...", "sender": "assistant", "text": "...", "created_at": "..."}
  ]
}]
```

### Claude Code Local
```jsonl
// ~/.claude/history.jsonl — one prompt per line
{"display":"the prompt text","timestamp":1774523330374,"sessionId":"..."}

// ~/.claude/projects/.../session-id.jsonl — full conversation
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"..."}]}}
```

## Implementation Plan

### Phase 1: ConversationStore + Importers
- `Sources/Deskfloor/Models/ConversationStore.swift` — core data model
- `Sources/Deskfloor/Importers/ClaudeCodeImporter.swift` — read local JSONL
- `Sources/Deskfloor/Importers/ChatGPTImporter.swift` — parse conversations.json
- `Sources/Deskfloor/Importers/ClaudeWebImporter.swift` — parse web export
- All persist to ~/.deskfloor/conversations.sqlite (too large for JSON)

### Phase 2: Session Timeline View
- New view mode in ContentView (Cmd+5)
- Horizontal swim lanes per provider
- Click to expand, color by project link

### Phase 3: Excerpt Board View
- New view mode (Cmd+6)
- Kanban columns: Prompts, Decisions, Dead Ends, Artifacts
- Drag between columns, drag to Composer

### Phase 4: Context Composer
- Floating panel (like launcher) or sidebar panel
- Drop zone for excerpts
- Token count, export to clipboard/Claude Code

### Phase 5: Session Inspector
- Detail view from timeline click
- Message annotations, bookmarks, artifact extraction
- "Rerun" button copies prompt to clipboard
