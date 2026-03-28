# Deskfloor Project Constitution

## Core Principles

### 1. Working software over impressive scaffolding

Every commit must leave the app in a runnable state where every visible feature
actually functions. "It compiles" is not a quality bar. "I clicked every button
and they all did what they said" is.

**Rule:** Before committing, manually test every changed view. If you can't test
it (no data, no network), don't commit it — write it to an Experiments/ file instead.

### 2. One thing at a time, done properly

Don't scaffold 5 features in parallel. Implement one feature completely — data model,
persistence, view, error handling, loading state — then move on.

**Rule:** No PR/commit touches more than 3 files unless it's a rename/refactor.
If your change spans 8 files, you're doing too many things at once.

### 3. Errors are user-visible events

Silent `catch { print(...) }` is forbidden. Every error the user might encounter
must surface in the UI as an alert, banner, or inline error state.

**Rule:** Every `catch` block must either throw (propagate), show a UI error, or
log AND set an error state that the view observes.

### 4. Data types don't know about views

Model types live in `Models/` and must compile without importing SwiftUI. Colors,
icons, labels for display are defined as view-side extensions in `Views/Extensions/`.

**Rule:** No `import SwiftUI` in any file under `Models/`, `Importers/`, or `Skein/`.

### 5. Views are small

No view file exceeds 200 lines. If it does, extract sub-views into separate files.

**Rule:** `wc -l Sources/Deskfloor/Views/*.swift` — every file under 200 lines.
Exception: ContentView may be up to 300 if it's mostly routing.

### 6. Shared patterns get shared implementations

If two files implement the same pattern (JSON persistence, relative dates, frecency
scoring), extract a shared utility.

**Rule:** Before writing a helper function, search the codebase. If it exists
elsewhere, extract to `Utilities/`.

### 7. Async operations have loading, success, and error states

Every operation that takes >100ms must show a loading indicator. Every operation
that can fail must have an error state. Every operation that succeeds must confirm.

**Rule:** Use `AsyncState<T>` for all async data:
```swift
enum AsyncState<T> {
    case idle
    case loading(progress: Double?)
    case loaded(T)
    case failed(String)
}
```

### 8. Keyboard shortcuts are discoverable

No invisible button hacks. Keyboard shortcuts live in `.commands { }` modifiers
or in proper NSMenu items. Users can find them in the menu bar.

**Rule:** Every keyboard shortcut has a corresponding menu item.

### 9. Tests exist for data processing

Importers, parsers, scorers, and persistence code must have unit tests with
fixture data. Views don't need tests (SwiftUI preview is the test).

**Rule:** Every file in `Models/`, `Importers/`, `Skein/` has a corresponding
test file with at least one test per public method.

### 10. The app starts fast

Cold launch to interactive must be under 2 seconds. No synchronous network calls,
no synchronous filesystem scans, no heavy computation on the main thread during
startup.

**Rule:** `init()` methods in stores load cached JSON only. Network fetches and
git scans are triggered by user action or after a delay.

---

## File Structure

```
Sources/Deskfloor/
├── DeskfloorApp.swift          # App entry, scene declarations only
├── AppKit/                     # AppKit integration (hotkey, panel, clipboard)
│   ├── HotkeyManager.swift
│   ├── LauncherWindowController.swift
│   └── ClipboardAction.swift
├── Models/                     # Data types + persistence (NO SwiftUI imports)
│   ├── Project.swift
│   ├── ProjectStore.swift
│   ├── FleetStore.swift
│   ├── PromptStore.swift
│   ├── HistoryStore.swift
│   ├── FrecencyTracker.swift
│   ├── LauncherItem.swift
│   └── Encumbrance.swift
├── Skein/                      # Conversation archaeology (NO SwiftUI imports)
│   ├── SkeinTypes.swift
│   └── SkeinStore.swift
├── Importers/                  # Data import (NO SwiftUI imports)
│   ├── ClaudeCodeImporter.swift
│   ├── ChatGPTImporter.swift
│   └── GitHubImporter.swift    # (move from Utilities/)
├── Utilities/                  # Shared helpers
│   ├── RelativeDate.swift
│   ├── JSONPersistence.swift
│   └── AsyncState.swift
├── Views/                      # All SwiftUI views (<200 lines each)
│   ├── ContentView.swift
│   ├── Board/
│   │   ├── BoardView.swift
│   │   └── ProjectCard.swift
│   ├── Perspective/
│   │   └── PerspectiveView.swift
│   ├── Timeline/
│   │   └── TimelineView.swift
│   ├── Graph/
│   │   └── GraphView.swift
│   ├── Skein/
│   │   ├── SkeinView.swift
│   │   ├── ThreadRow.swift
│   │   ├── ThreadDetailView.swift
│   │   └── TurnRow.swift
│   ├── Launcher/
│   │   ├── LauncherPanelView.swift
│   │   ├── LauncherRow.swift
│   │   └── LauncherFooter.swift
│   ├── Shared/
│   │   ├── ErrorBanner.swift
│   │   ├── FilterBar.swift
│   │   └── StatPill.swift
│   ├── Extensions/
│   │   ├── SessionStatus+View.swift
│   │   ├── Perspective+View.swift
│   │   └── ThreadSource+View.swift
│   ├── SidebarView.swift
│   └── ProjectDetailSheet.swift
└── Tests/
    ├── ClaudeCodeImporterTests.swift
    ├── ChatGPTImporterTests.swift
    ├── ProjectStoreTests.swift
    └── FrecencyTrackerTests.swift
```

---

## Code Review Checklist

Before every commit, verify:

- [ ] App launches in under 2 seconds
- [ ] Every visible button/control does something when clicked
- [ ] No silent catch blocks (search for `catch {` and verify each one)
- [ ] No SwiftUI imports in Models/, Importers/, Skein/
- [ ] No view file over 200 lines
- [ ] Keyboard shortcuts are in menu items, not invisible buttons
- [ ] Async operations show loading/error states
- [ ] Changed features tested by actually using them in the running app

---

## What This Replaces

This constitution replaces the "move fast and scaffold" approach that produced
28 files in 4 hours but left half of them non-functional. The new approach:
slower commits, each one a verified improvement.
