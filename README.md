# Deskfloor

SwiftUI macOS app. Project intelligence dashboard with a global launcher, fleet monitoring, and experimental conversation threading.

## What it does

**Dashboard** with 6 view modes:
- **Board** -- kanban-style project cards showing git status, language, and activity
- **Perspective** -- grid layout filtered by project perspective/status
- **Timeline** -- project activity over time
- **Graph** -- relationship graph between projects
- **Skein** -- experimental conversation thread viewer (threads from Claude Code, Claude.ai, ChatGPT, AgentSlack, Codex)
- **Paste** -- clipboard analysis view

**Launcher** (Option+Space hotkey):
- Spotlight-like floating panel for quick access to projects, fleet hosts, tmux sessions, saved prompts, and shell history
- Frecency-ranked results
- Opens iTerm via AppleScript for SSH and local project directories

**Fleet monitoring**:
- Polls AgentSlack API for host metrics (load, memory, disk, Claude process count, tmux sessions)
- 5 configured hosts: hyle, finml, hub2, karlsruhe, nabla
- Menu bar extra with fleet status and one-click SSH jump

**Project scanning**:
- Auto-discovers projects under `~/Nissan/` by looking for manifest files (Package.swift, package.json, Cargo.toml, pyproject.toml, etc.)
- Reads git log for commit count, last activity, branch info

## Dependencies

- NLPEngine from `../nlp-engine` (local package dependency)
- macOS 14+, Swift 5.10

## Build

```
swift build
```

## Run

```
swift run Deskfloor
```

## Current status

Working but in active development. The dashboard, launcher, fleet polling, and project scanning all function. The Skein view is experimental -- types are defined but the viewer is early. Some views (Graph, Dispatch) are more complete than others.

## What's next

- Skein view: full conversation threading with cross-source timeline
- Project health scoring based on git activity patterns
- Dispatch view for multi-project batch operations
- Tighter integration with corpora-bridge corpus data
