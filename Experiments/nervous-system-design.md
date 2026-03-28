# Deskfloor as Nervous System — Background Acquisition + Processing + Surfacing

## The Three Flows

### Flow 1: Acquisition (always running, background)

The app continuously gathers data from the environment without user action:

```
SOURCES (background polling)          FREQUENCY     WHAT WE GET
─────────────────────────────────────────────────────────────────
AgentSlack /fleet/metrics             30s           host load, disk, mem, claude count
AgentSlack /tmux/sessions             30s           session names, window counts, attached
AgentSlack /agents                    60s           agent list, online status, spheres
AgentSlack /history/{channel}         5min          new messages across channels
Coggy /api/metrics                    60s           bridge verdict, funds, grounding rate
GitHub Actions (gh run list)          5min          CI status per repo (green/red/pending)
Local git (git status)                on focus      dirty files, branch, unpushed commits
~/.claude/history.jsonl               on paste/open new prompts, session IDs
~/.claude/projects/*/*.jsonl          on skein open new conversation turns
Clipboard                             1s            detect prompts, code, URLs
File system ~/Nissan/                 on scan       new repos, changed files
SSH host checks                       10min         reachability, basic health
```

Each source feeds into a **DataBus** — a central observable store that other
subsystems subscribe to.

### Flow 2: Processing (reactive, triggered by new data)

When new data arrives, background processors enrich it:

```
NEW DATA                    PROCESSOR                  OUTPUT
─────────────────────────────────────────────────────────────────
New fleet metrics           AlertDetector              Alerts: disk>90%, load>5, service down
New CI status               CIStatusMapper             Badge updates on project cards
New git status              DirtyDetector              "3 dirty" badges, stale detection
New conversation            TopicExtractor (NLP)       Keywords, topic assignment
New clipboard text          PromptDetector (NLP)       "This looks like a prompt" suggestion
New agent message           ThreadLinker               Associates message with project
Host health change          FleetDigester              Fleet summary for AgentSlack post
Multiple changes            AttentionRanker            "What needs attention" sorted list
```

### Flow 3: Surfacing (UI, what the user sees)

Processed data surfaces in the right place at the right time:

```
WHERE IT SURFACES              WHAT                           TRIGGER
─────────────────────────────────────────────────────────────────
Fleet bar (always visible)     Host health + alerts           Every 30s poll
Project card badges            CI status, git dirty count     On data change
Attention sidebar              "3 things need attention"      On alert
Launcher search results        Enriched with live status      On Ctrl+Space
Skein thread list              New conversations auto-appear  On skein open
Notification (macOS)           Critical alerts                When disk>95%, service down
Menu bar icon color            Green/yellow/red fleet health  On fleet change
Loom auto-suggestions          "This paste mentions nabla"    On paste analyze
```

## The DataBus

A single observable object that all subsystems read from:

```swift
@Observable
final class DataBus {
    // Fleet
    var fleetMetrics: [String: HostMetrics] = [:]
    var fleetAlerts: [FleetAlert] = []
    var tmuxSessions: [String: [TmuxSession]] = [:]

    // CI
    var ciStatus: [String: CIRun] = [:]  // repo name → latest run

    // Git
    var gitStatus: [String: GitStatus] = [:]  // repo path → status

    // Conversations
    var recentPrompts: [RecentPrompt] = []
    var activeThreads: [Thread] = []

    // Attention
    var attentionItems: [AttentionItem] = []

    // Clipboard
    var lastClipboardAnalysis: ClipboardAnalysis?
}
```

Every view subscribes to the parts it needs. No polling from views.
The DataBus is the single source of truth.

## Attention Items — The Key Abstraction

An AttentionItem is anything that needs the user's awareness:

```swift
struct AttentionItem: Identifiable {
    let id: UUID
    let severity: Severity      // critical, warning, info
    let source: String          // "fleet:gcp1", "ci:coggy", "git:deskfloor"
    let title: String           // "gcp1 disk at 93%"
    let detail: String          // "742MB free. Clean /var/log or expand disk."
    let actions: [Action]       // [.sshTo("gcp1"), .openURL("...")]
    let detectedAt: Date
    var acknowledged: Bool

    enum Severity { case critical, warning, info }
    enum Action {
        case sshTo(String)
        case openURL(URL)
        case runCommand(String, host: String?)
        case dispatch(context: String)
        case openProject(UUID)
    }
}
```

The Attention sidebar (or overlay) shows these sorted by severity then recency.
Each has action buttons: "SSH to gcp1", "Open CI", "Dispatch fix agent".

## Background Acquisition Architecture

```
┌─────────────────────────────────────────────────────┐
│                    DataBus                            │
│  (single @Observable, MainActor)                     │
├─────────────────────────────────────────────────────┤
│                                                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐            │
│  │FleetPoller│ │CIPoller  │ │GitScanner│            │
│  │ 30s cycle │ │ 5min     │ │ on focus │            │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘            │
│       │             │            │                   │
│  ┌────▼─────┐ ┌────▼─────┐ ┌───▼──────┐            │
│  │AlertDetect│ │CIMapper  │ │DirtyDetect│           │
│  └────┬─────┘ └────┬─────┘ └───┬──────┘            │
│       │             │            │                   │
│       └─────────────┼────────────┘                   │
│                     ▼                                │
│            AttentionRanker                           │
│            (combines all signals)                    │
│                     │                                │
│                     ▼                                │
│          attentionItems: [AttentionItem]             │
│                                                      │
└─────────────────────────────────────────────────────┘
         │                    │                 │
         ▼                    ▼                 ▼
   Fleet Bar            Attention          Project Cards
   (badges)             Sidebar            (CI badges)
```

## UX Flows for Background Intelligence

### Flow A: "I just opened Deskfloor after lunch"

1. Fleet bar shows: hyle ✓, finml ⚠ (load 9), hub2 ✓, gcp1 🔴 (disk 93%), nabla ⚠ (load 2)
2. Attention overlay slides in: "2 critical, 1 warning"
   - 🔴 gcp1 disk at 93% [SSH] [Clean disk]
   - 🔴 finml soft lockup [SSH] [Kill process]
   - ⚠ nabla gemini at 45% CPU [SSH] [Check]
3. User clicks [SSH] on gcp1 → iTerm opens, connected
4. Attention item marks as "in progress"

### Flow B: "I just pushed code to coggy"

1. Git scanner detects: coggy is clean, 1 commit ahead of origin
2. CI poller detects: new run triggered on uprootiny/coggy
3. Project card for coggy shows: 🟡 CI running
4. 3 minutes later: CI poller detects green → card shows ✅
5. If CI fails: attention item appears with error log excerpt

### Flow C: "I'm reading a session transcript someone pasted"

1. User pastes into Loom
2. Parser detects: references to nabla, gcp1, solvulator, gemini
3. DataBus enriches: "nabla is currently at load 2, gemini running in session main"
4. Loom shows enriched cards: the nabla command sections show live host status
5. User clicks [Jack In] on a nabla piece → iTerm opens SSHd to nabla, attaches tmux main

### Flow D: "I dispatched an agent 20 minutes ago"

1. User dispatched a claude session to hyle working on coggy
2. DataBus's fleet poller notices: hyle.claude_count went from 8 to 9
3. DataBus's git scanner notices: coggy has new commits
4. Project card for coggy shows: "Agent active" badge + "2 new commits"
5. User can click: [View commits] [Attach session] [Stop agent]

## What This Means for Implementation

The DataBus replaces the current scattered polling:
- FleetStore → DataBus.fleetMetrics
- ProjectStore.refreshGitInfo → DataBus.gitStatus
- PromptStore → DataBus.recentPrompts

All background work runs on `Task.detached(priority: .utility)`.
All UI updates happen on `@MainActor` through the DataBus.

The Attention sidebar is the single most valuable new UI element —
it answers "what needs my attention right now?" without the user
having to scan 200 project cards.

## Priority

1. **DataBus core** — single observable, fleet + git + CI slots
2. **FleetPoller** — move existing FleetStore polling into DataBus
3. **AttentionItem** — define the struct, add an attention sidebar
4. **AlertDetector** — disk>90%, load>5, service down → AttentionItems
5. **CIPoller** — `gh run list` for repos with workflows
6. **Enriched Loom** — paste analysis reads from DataBus for live context
