# Deskfloor Architecture — Subsystem Map

Deskfloor is **five subsystems**, each with clear scope and meaning.
Each must be complete and tidy in itself before the next is built.

---

## 1. Atlas — The Project Board

**Scope:** See all your projects. Filter, sort, group, assess status at a glance.

**What it does:**
- Imports 200 repos from GitHub via `gh` CLI
- Scans ~/Nissan/ for local clones with git info (branch, dirty, commits)
- Four views: Board (status columns), Perspective (domain columns), Timeline (Gantt), Graph (connections)
- Sidebar filtering by perspective, status, encumbrances
- Project detail sheet with all metadata

**Score: 7/10.** Views render, import works, filtering works, drag-drop works.
Missing: card click is inconsistent, graph connections are weak heuristics, no CI status.

**Files:**
- Models: Project.swift, ProjectStore.swift, Encumbrance.swift
- Views: BoardView, PerspectiveView, TimelineView, GraphView, ProjectCard, ProjectDetailSheet, SidebarView, ContentView
- Importers: GitHubImporter.swift

---

## 2. Helm — The Command Surface

**Scope:** Point at things and make them happen. The action layer.

**What it does:**
- Right-click any project → Run Agent Session (opens iTerm + claude in that repo)
- Right-click → Open in iTerm, Open on GitHub, Set Status
- Multi-select with Cmd+Click → batch actions
- Dispatch panel: compose structured context from selected projects → copy or launch claude
- Fleet bar: click any host → SSH via iTerm
- Launcher panel (Ctrl+Space): fuzzy search over hosts, sessions, prompts, projects, history

**Score: 5/10.** Right-click works, fleet bar SSH works, dispatch panel exists.
Missing: multi-select untested, launcher flaky, no agent progress tracking, no CI actions.

**Files:**
- Views: DispatchView.swift, LauncherPanel.swift
- AppKit: HotkeyManager.swift, LauncherWindowController.swift, ClipboardAction.swift
- Models: LauncherItem.swift, FleetStore.swift, PromptStore.swift, HistoryStore.swift, FrecencyTracker.swift

---

## 3. Skein — Conversation Archaeology

**Scope:** Find, annotate, excerpt, and recompose past LLM conversations.

**What it does:**
- Imports Claude Code conversations (79 local JSONL files)
- Imports ChatGPT exports (conversations.json)
- Thread list with status (live/paused/abandoned/crashed), topics, turn counts
- Turn-by-turn detail with tool loop badges, artifact detection
- Bookmark/dead-end/breakthrough markers on turns
- Full-text search across turn content
- Auto-import on view open

**Score: 4/10.** Data model is solid, importer works, basic list+detail renders.
Missing: excerpt board (Loom), composition panel (Shuttle), splicing, keyboard nav.

**Files:**
- Skein: SkeinTypes.swift, SkeinStore.swift
- Importers: ClaudeCodeImporter.swift, ChatGPTImporter.swift
- Views: SkeinView.swift

---

## 4. Loom — The Paste & Analysis Workshop

**Scope:** Paste any text, have it parsed into sections, select and dispatch.

**What it does:**
- Paste session transcripts into a text editor
- Auto-analyze into typed sections: Prompt, Response, Code, Command, Commit, CI, Reflection, Table, Error
- Each section: selectable, copyable, dispatchable
- Multi-select → Copy Selected or Dispatch Selected (opens claude with context)

**Score: 3/10.** Parser exists, view renders, dispatch button works.
Missing: better parsing accuracy, drag-out to other views, persistent excerpts, connection to Skein.

**Files:**
- Views: PasteAnalysisView.swift

---

## 5. Watchtower — Fleet & Observability

**Scope:** Live view of server fleet, agent sessions, health metrics.

**What it does:**
- Polls AgentSlack API every 30s for host metrics (load, disk, mem, claude count, tmux count)
- Fleet bar at bottom of every view showing all hosts
- Click host → SSH in iTerm
- Launcher shows hosts + tmux sessions
- Menu bar with fleet quick-access

**Score: 6/10.** Polling works, fleet bar renders, SSH works.
Missing: tmux session list only for hyle, no CI status polling, no agent progress tracking, no alerts.

**Files:**
- Models: FleetStore.swift
- Views: fleet bar in ContentView, fleet entries in LauncherPanel

---

## Subsystem Dependencies

```
           Atlas (project data)
          ╱     ╲
    Helm ─────── Skein
    (actions)    (conversations)
          ╲     ╱
      Loom ──── Watchtower
    (analysis)   (fleet)
```

Atlas is the data backbone — Helm and Skein both read from it.
Loom can feed excerpts into Skein (future).
Watchtower informs Helm (which host to dispatch to).

## Completion Order

1. **Atlas → 9/10.** Add CI status badge, fix graph connections. Solid foundation.
2. **Helm → 7/10.** Test multi-select, fix launcher reliability, add agent progress.
3. **Watchtower → 8/10.** Add tmux sessions for all hosts, CI polling, basic alerts.
4. **Skein → 6/10.** Full-text search working, add keyboard nav, pull action, excerpt extraction.
5. **Loom → 5/10.** Better parsing, persistent excerpts, drag to Skein/Shuttle.

Each subsystem should be raised to its target score before moving to the next.
No new subsystem until the existing ones are at target.
