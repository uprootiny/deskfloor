# Deskfloor Launcher — Implementation Plan

## Current State

13 source files, 1,737 lines of Swift. Builds clean with NLPEngine dependency.

Existing: ProjectStore, FleetStore, LauncherPanel, LauncherItem+Search, MenuBarExtra, iTerm AppleScript integration, 4 dashboard view modes (board, perspective, timeline, graph), GitHub import.

**Gaps:** No global hotkey, no NSPanel (uses SwiftUI Window), no tmux sessions in FleetStore, no PromptStore/HistoryStore, no frecency, not an LSUIElement.

---

## Phase 1: NSPanel + Global Hotkey (Foundation)

**Goal:** Floating panel via NSPanel, global hotkey via Carbon RegisterEventHotKey, hide from Dock.

**Create:**
- `Sources/Deskfloor/AppKit/HotkeyManager.swift` (~50 lines) — Carbon `RegisterEventHotKey`, Option+Space default. Uses `Unmanaged.passUnretained(self).toOpaque()` for callback context.
- `Sources/Deskfloor/AppKit/LauncherWindowController.swift` (~80 lines) — `NSPanel` subclass (`canBecomeKey=true`, `canBecomeMain=false`), `.nonactivatingPanel` style, `.floating` level, `.canJoinAllSpaces`. Toggle show/hide. Center on screen.

**Modify:**
- `DeskfloorApp.swift` — Remove `Window("Launcher")` scene. Add HotkeyManager + LauncherWindowController as @State. Wire hotkey→toggle. Add `NSApp.setActivationPolicy(.accessory)` for LSUIElement behavior.

**Verify:** Option+Space toggles panel. Panel floats above other apps. Search field receives keystrokes. Escape dismisses. App not in Dock. MenuBarExtra still works.

**Effort:** 1 session.

---

## Phase 2: Tmux Sessions

**Goal:** FleetStore fetches `/tmux/sessions` from AgentSlack. Sessions appear in launcher.

**Modify:**
- `Models/FleetStore.swift` — After `/fleet/metrics`, fetch `/tmux/sessions`. Parse `[{name, windows, attached}]`. Assign to hyle's `sessions` array.

**Verify:** Launcher shows tmux sessions under hyle. Click attaches via iTerm.

**Effort:** Half session.

---

## Phase 3: PromptStore + Shell History

**Goal:** Add prompts and shell history as searchable launcher items.

**Create:**
- `Models/PromptStore.swift` (~60 lines) — JSON-backed prompt library at `~/.deskfloor/prompts.json`. Title, content, tags, useCount, lastUsed.
- `Models/HistoryStore.swift` (~80 lines) — Reads `~/.zsh_history`, parses extended format (`: timestamp:0;command`), ranks by frecency.

**Modify:**
- `Models/LauncherItem.swift` — Add `.prompt(PromptStore.Prompt)` and `.historyCommand(HistoryStore.HistoryCommand)` cases.
- `Views/LauncherPanel.swift` — Include prompts and history in `allItems`.
- `DeskfloorApp.swift` — Add PromptStore + HistoryStore. Handle actions: prompt→copy to clipboard, history→open in iTerm.

**Effort:** 1 session.

---

## Phase 4: Keyboard Polish

**Goal:** Arrow keys scroll into view, Tab cycles categories, Cmd+Enter copies, query reset.

**Create:**
- `AppKit/ClipboardAction.swift` (~25 lines) — `copyOnly()` and `copyAndPaste()` (CGEvent Cmd+V simulation).

**Modify:**
- `Views/LauncherPanel.swift` — ScrollViewReader + `scrollTo` on selection change. Tab handler for category cycling. Cmd+Enter for copy. `onChange(of: query)` resets selectedIndex. Action hint labels on rows ("SSH", "Attach", "Paste", "Run").

**Effort:** 1 session.

---

## Phase 5: Frecency Scoring

**Goal:** Recently and frequently used items rank higher.

**Create:**
- `Models/FrecencyTracker.swift` (~50 lines) — JSON at `~/.deskfloor/frecency.json`. Score = count × recency weight (last 6h=100, day=80, 3d=60, week=40, month=20, older=10).

**Modify:**
- `Models/LauncherItem.swift` — `LauncherSearch.search()` uses frecency as tiebreaker. Empty query sorts by frecency.
- `DeskfloorApp.swift` — `frecency.recordAccess(itemID:)` on every action.

**Effort:** Half session.

---

## Phase 6: Visual Polish

**Modify:**
- `AppKit/LauncherWindowController.swift` — Fade+scale animation on show (0.15s ease-out). Click-outside dismiss via `NSEvent.addGlobalMonitorForEvents`.
- `Views/LauncherPanel.swift` — Toast message after actions ("Connecting...", "Copied"). Brief delay before dismiss.

**Effort:** Half session.

---

## Phase 7: Extended Sources (Bookmarks + Local Repos)

**Create:**
- `Models/BookmarkStore.swift` (~40 lines) — URL bookmarks at `~/.deskfloor/bookmarks.json`.
- `Models/RepoScanner.swift` (~45 lines) — Scans `~/Nissan/` for `.git` directories.

**Modify:**
- `Models/LauncherItem.swift` — Add `.bookmark` and `.localRepo` cases.
- `DeskfloorApp.swift` — Wire actions: bookmark→open URL, localRepo→open in Finder.

**Effort:** 1 session.

---

## Phase 8: Preferences

**Create:**
- `Views/PreferencesView.swift` (~100 lines) — TabView with General (hotkey config), Fleet (poll interval, AgentSlack URL), Search (scan directories, history limit).

**Modify:**
- `DeskfloorApp.swift` — Add `Settings { PreferencesView() }` scene.
- `AppKit/HotkeyManager.swift` — Re-register on preference change.

**Effort:** 1 session.

---

## Dependency Graph

```
Phase 1 ──→ Phase 2 ──→ Phase 3 ──→ Phase 4
                              │         │
                              ├──→ Phase 5
                              │
                              └──→ Phase 6
                                     │
                                     └──→ Phase 7 ──→ Phase 8
```

Phases 4 and 5 can run in parallel. Phase 6 can start after Phase 1.

## File Manifest

| New File | Phase | Est. Lines |
|----------|-------|-----------|
| AppKit/HotkeyManager.swift | 1 | 50 |
| AppKit/LauncherWindowController.swift | 1 | 80 |
| Models/PromptStore.swift | 3 | 60 |
| Models/HistoryStore.swift | 3 | 80 |
| AppKit/ClipboardAction.swift | 4 | 25 |
| Models/FrecencyTracker.swift | 5 | 50 |
| Models/BookmarkStore.swift | 7 | 40 |
| Models/RepoScanner.swift | 7 | 45 |
| Views/PreferencesView.swift | 8 | 100 |

**Total new:** ~530 lines across 9 files.
**Total modified:** 5 existing files (DeskfloorApp, LauncherItem, LauncherPanel, FleetStore, Package.swift).
**Untouched:** 8 dashboard files (BoardView, PerspectiveView, TimelineView, GraphView, SidebarView, ProjectCard, ProjectDetailSheet, ContentView).
