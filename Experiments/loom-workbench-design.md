# Loom Workbench — Deep Design

## What the user just described

> "a view to capture that and tear it apart properly and associate various
> pieces with various hosts and sessions and repos and files and intents
> and functions and formats and shapes and so on and have overlays and
> affordances to copy or execute or jack in to some of these pieces"

This is not a parser. This is an **analytical workbench** for operational text.

## The Pieces and Their Associations

Every piece in a paste has multiple dimensions:

| Dimension | Examples | How to detect |
|-----------|----------|---------------|
| **Host** | hyle, finml, nabla, gcp1, local | SSH commands, hostnames, IPs, tmux session names |
| **Session** | claude code, gemini, shell, tmux | Tool prefixes (⏺), prompt chars (❯), TUI frames |
| **Repo** | solvulator, BespokeSynth, deskfloor | Directory paths, git operations, package names |
| **File** | serve.py, IDrawableModule.cpp | File paths in tool calls, imports, error traces |
| **Intent** | fix, build, deploy, investigate, design | Verb analysis in prompts, commit messages |
| **Function** | parse, render, connect, dispatch | Function names in code, tool names |
| **Format** | code, markdown, JSON, table, shell output | Syntax patterns, delimiters |
| **Shape** | prompt→response, command→output, error→fix | Sequential pairing of related pieces |

## The Workbench Layout

```
┌─────────────────────────────────────────────────────────────────────────┐
│ LOOM WORKBENCH                                                          │
│ [Paste] [Analyze] [Auto-tag]     Keywords: fleet, dispatch, gemini...   │
├────────┬────────────────────────────────────────────────────┬───────────┤
│        │                                                    │           │
│ FACETS │  PIECES                                            │ COMPOSER  │
│        │                                                    │           │
│ HOST   │  ┌─ nabla ──────────────────────────────────────┐  │ [piece 1] │
│ ● hyle │  │ ⏺ Shell: tmux send-keys -t main '2' Enter   │  │ [piece 2] │
│ ○ finml│  │ Thread: nabla:gemini · Kind: Command         │  │ [piece 3] │
│ ● nabla│  │ [Copy] [Execute] [Jack In]                   │  │           │
│ ○ gcp1 │  └──────────────────────────────────────────────┘  │ prompt:   │
│        │                                                    │ [______]  │
│ SESSION│  ┌─ deskfloor ─────────────────────────────────┐  │           │
│ ● claude│ │ ⏺ Update(DispatchView.swift)                │  │ ~800 tok  │
│ ○ gemin│  │ Thread: deskfloor · Kind: Code · File: ...   │  │ [Dispatch]│
│ ○ shell│  │ [Copy] [Open File] [Diff]                    │  │           │
│        │  └──────────────────────────────────────────────┘  │           │
│ REPO   │                                                    │           │
│ ● desk…│  ┌─ finml ─────────────────────────────────────┐  │           │
│ ○ solvu│  │ Java at 311% CPU — soft lockup               │  │           │
│ ○ besp…│  │ Thread: finml · Kind: Error · Host: finml    │  │           │
│        │  │ [Copy] [SSH to finml] [Kill Process]          │  │           │
│ INTENT │  └──────────────────────────────────────────────┘  │           │
│ ○ fix  │                                                    │           │
│ ● build│                                                    │           │
│ ○ deplo│                                                    │           │
│ ● inves│                                                    │           │
│        │                                                    │           │
│ KIND   │                                                    │           │
│ 12 Cmd │                                                    │           │
│  8 Resp│                                                    │           │
│  5 Prom│                                                    │           │
│  3 Code│                                                    │           │
│  2 Err │                                                    │           │
│  2 CI  │                                                    │           │
├────────┴────────────────────────────────────────────────────┴───────────┤
│ 🜂 hyle 3 75% │ 🜄 finml 9 89% │ 🜁 hub2 1 67% │ ☁ gcp1 0 93%        │
└─────────────────────────────────────────────────────────────────────────┘
```

## The Facet Sidebar (left)

Not just filters — **faceted navigation**. Each facet shows counts and lets you
combine filters. Clicking "nabla" under HOST + "Command" under KIND shows only
commands that ran on nabla.

Facets are auto-extracted from the paste:
- **Host:** Detected from SSH commands, IPs, hostnames
- **Session:** Detected from tool prefixes, TUI patterns
- **Repo:** Detected from directory paths, git operations
- **Intent:** Detected from verbs in prompts (fix, build, investigate, deploy, design)
- **Kind:** The existing section types (Prompt, Command, Code, etc.)
- **File:** Extracted from file paths in tool calls

Each facet entry shows a count and is toggleable. Multiple selections within a
facet = OR. Selections across facets = AND.

## The Piece Card (center)

Each piece is a card with:

**Header line:**
- Thread badge (colored by host)
- Kind badge (existing icon+color)
- Title (first meaningful line)

**Metadata line:**
- Host, Session, Repo, File (if detected)
- Character count, line count

**Content:** Collapsed by default, expandable to full monospace text.

**Action buttons (the key part):**
- **Copy** — to clipboard
- **Execute** — if it's a command, run it (locally or via SSH to detected host)
- **Jack In** — open iTerm SSHd to the detected host + directory
- **Open File** — if a file is referenced, open it in editor
- **To Composer** — add to the composition panel
- **Diff** — if it's a code change, show before/after

Actions are contextual — a Command piece shows Execute, a Code piece shows
Open File, a Host reference shows Jack In.

## The Composer (right)

Same as current but enhanced:
- Pieces can be reordered by drag
- Each piece shows which facets it carries (host, repo, intent)
- The composed context auto-detects the right dispatch target:
  - If all pieces are about nabla → dispatch to nabla
  - If pieces span hosts → dispatch locally with context
  - If pieces are about a specific repo → cd to that repo first

## Detection Algorithms

### Host Detection
```
if content matches /ssh\s+(\w+)/ → host = $1
if content contains IP matching fleet → host = fleet[IP].name
if content contains "uprootiny@hostname" → host = hostname
if content contains tmux session name known to be on host → host
```

### Repo Detection
```
if content contains "/Users/uprootiny/Nissan/(\w+)" → repo = $1
if content contains "gh repo clone (\S+)" → repo = $1
if content contains "git commit" near "(\w+)/" path → repo
if content references Package.swift/Cargo.toml/etc in path → repo from path
```

### Intent Detection
```
verbs = extract_verbs(prompts_only)
intent_map = {
  fix/repair/debug/resolve → "fix"
  build/compile/make → "build"
  deploy/ship/release/push → "deploy"
  investigate/check/probe/triage → "investigate"
  design/plan/architect/brainstorm → "design"
  install/setup/configure → "setup"
  clean/remove/delete/prune → "cleanup"
}
```

### File Detection
```
scan for patterns:
  Sources/Deskfloor/Views/\w+\.swift
  ~/Nissan/\w+/\w+\.\w+
  /home/uprootiny/\w+/\w+
  \w+\.(swift|rs|clj|py|js|ts|cpp|h|md|yml|json)
```

## Implementation Order

1. **Facet extraction** — post-process parsed sections to detect hosts, repos, intents, files
2. **Facet sidebar** — SwiftUI List with toggleable facet entries
3. **Enhanced piece cards** — contextual action buttons based on detected facets
4. **Execute action** — run detected commands locally or via SSH
5. **Jack In action** — open iTerm to detected host+directory
6. **Smart dispatch** — auto-detect target from composer contents
