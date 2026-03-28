# Skein UX Design — First Principles

*Produced by design subagent after reading the full codebase*

## Part 1: Intent — The Five Things Users Open Skein To Do

1. **Find a specific past exchange.** "Where did I get that NixOS derivation working?" The user has a vague memory — a topic, a tool, a time window, or an outcome — and needs to locate it across 79+ threads and 4000+ turns.

2. **Assess the state of ongoing work.** "What did I leave running? What crashed?" This happens at session start. Fast visual scan of status dots. Not reading content — reading status.

3. **Resume an abandoned thread.** "I was halfway through BespokeSynth builds three days ago." Locate thread, scan turns, copy context for a new session.

4. **Extract reusable material.** "That prompt pattern for reviewing architecture — save it separately." Pull pieces out of threads into the excerpt board.

5. **Compose a new context from old pieces.** "Claude needs to understand three things from three different sessions." Assemble multi-source prompts.

## Part 2: The Skein Metaphor — Concrete UI Mappings

| Metaphor | Action | Gesture |
|----------|--------|---------|
| Pull | Resume a thread | Select → Enter → copies context to pasteboard |
| Dye | Tag/color a thread | Right-click → Dye → pick color or type tag |
| Unravel | Inspect turn-by-turn | Double-click or Space → detail pane expands |
| Splice | Connect turns across threads | Drag turn-to-turn or Cmd+J |
| Wind | Compose from excerpts | Drag turns into Shuttle panel |
| Snip | Mark dead end | Press D → red indicator on turn |
| Mark | Bookmark / breakthrough | Press B or G → gold/green indicator |

## Part 3: Information Architecture

### Critical Design Decision: List First, Not Timeline

The timeline (canvas view) is the **wrong default**. 80% of Skein interactions are "find something" or "check status" — both best served by a filterable, sortable list. The timeline is a secondary mode for the 20% of temporal exploration.

### Default Layout

```
┌──────────────────────────────────────────────────────────────────┐
│ [Search...]  Source:[All ▾]  Status:[All ▾]   42 threads  [+]   │
├──────────────┬───────────────────────────────────────────────────┤
│              │                                                   │
│  THREAD LIST │  DETAIL PANE                                      │
│  (sidebar)   │                                                   │
│              │  Thread title + status + stats                    │
│  ● Thread A  │  Topic pills                                      │
│  ○ Thread B  │  ──────────────────────                           │
│  ◌ Thread C  │  Turn 1: user content (3 lines max)               │
│  ⚠ Thread E  │    [Bash] [Read] [Edit]  ← tool pills            │
│              │  Turn 2: ★ bookmarked turn                        │
│              │  Turn 3: user content...                          │
│              │                                                   │
├──────────────┴───────────────────────────────────────────────────┤
│ [List] [Timeline]  ·  3 live · 12 paused · 8 abandoned          │
└──────────────────────────────────────────────────────────────────┘
```

### Search Must Hit Turn Content

When the user types "nixos derivation", they need to find the thread where that phrase was used, even if the thread title is "bootstrap & discovery." Search must scan `turn.userContent` and `turn.assistantContent`. At 4000 turns × 200 words = 800K words, naive `String.contains` takes <50ms. No index needed.

## Part 4: Flow

### 30-second: "Is anything still running?"
1. Cmd+5 → Skein. Eyes scan status dots.
2. Green = live, yellow = paused, red triangle = crashed.
3. Click crashed thread → see last turns with error.
4. Done.

### 5-minute: "Find the prompt that worked"
1. Type "fleet metrics" in search. List narrows to 4 threads.
2. Click most recent. Detail shows turns.
3. Cmd+F → "endpoint" → jumps to turn 23 (green breakthrough marker).
4. Click [Copy Prompt]. Switch to Claude Code, paste.

### 30-minute: "Build a context document"
1. Find Thread A, expand turn 12. Click [→ Shuttle].
2. Find Thread B, expand turn 7. Click [→ Shuttle].
3. Find Thread C, turn 3. Click [→ Shuttle].
4. Open Shuttle. Three excerpt cards. Reorder by dragging.
5. Type prompt at bottom. Token estimate: ~2400.
6. Click [Copy All]. Paste into new session.

## Part 5: Affordances

### Immediately graspable
- Status dots (color = state)
- Search field (top, magnifying glass)
- Thread list + detail pane (standard macOS sidebar)
- Expand/collapse chevrons on every turn
- Copy button on every turn

### Discoverable in first session
- B/D/G keyboard shortcuts (bookmark/dead-end/breakthrough)
- Drag turns to Shuttle
- Clickable status counts in footer
- In-thread search (Cmd+F)
- Timeline toggle

### Requires learning
- Splicing (Cmd+J)
- Composition workflow
- Loom column categorization

## Part 6: Keyboard

| Key | Context | Action |
|-----|---------|--------|
| ↑/↓ | Thread list | Move selection |
| ↑/↓ | Detail pane | Move turn selection |
| Tab | Anywhere | Toggle focus list ↔ detail |
| Enter | Thread list | Focus detail pane |
| Enter | Turn selected | Expand/collapse |
| Space | Thread list | Quick preview (popover) |
| B | Turn | Toggle bookmark |
| D | Turn | Toggle dead end |
| G | Turn | Toggle breakthrough |
| Cmd+C | Turn | Copy user prompt |
| Cmd+Shift+C | Turn | Copy prompt + response |
| E | Turn | Extract to Loom |
| Cmd+F | Detail pane | In-thread search |
| / | List focused | Focus search field |
| S | Thread | Cycle status |
| Esc | Anywhere | Clear / close / blur |

## Part 7: What NOT to Build

1. **Not a chat replay.** No alternating bubbles. Turn list with collapsed prompts is correct — scannable, filterable, excerpt-friendly. Chat UI is none of those.

2. **Not real-time sync.** Don't auto-refresh during Claude Code sessions. Import after, not during. Manual "Refresh" button.

3. **Not AI auto-tagging.** NLP keyword extraction + manual tags + search is enough.

4. **Not a diff view.** Threads diverge unpredictably. Splices are the right tool.

5. **Not collaborative.** Bus factor = 1. Single user.

6. **Not timeline-first.** List is the primary interface. Timeline is secondary.

7. **Not separate windows.** Loom and Shuttle are panels within Skein, not new windows. Context must be preserved.

## Part 8: Implementation Priority

1. **Make the list work.** Full-text search across turns, flat sort option, in-thread Cmd+F, status filter pills, keyboard nav, "Pull" action.
2. **Loom panel.** Slide-over within Skein. Five-column excerpt board.
3. **Shuttle panel.** Right-docked composition panel. Drag from Loom/detail. Token counter. Dispatch.
4. **Timeline mode.** Canvas-based temporal view. Secondary.
5. **Splicing.** Cross-thread connections. Last — depends on populated annotations.

## Part 9: Performance

- 79 threads → 500 expected. In-memory JSON viable to ~1000 threads.
- Full-text search over 5M words: 30-80ms. No index needed with 150ms debounce.
- LazyVStack for turns, List for threads — already lazy.
- Hebrew text: SwiftUI handles RTL within LTR natively. No special handling.

## Part 10: Open Questions

1. Should Skein hide the project sidebar or replace it with thread list?
2. Should excerpts be global or per-project? (Probably global.)
3. How should "dispatch" work? Pasteboard + iTerm AppleScript? Claude CLI `--context`?
4. Should Skein auto-import on launch? (Yes — 1-2 second scan is worth it.)
