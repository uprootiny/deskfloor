# Deskfloor Engineering Critique

## The Numbers

- 28 Swift files, ~2,800 lines of source
- 11 commits in 4 hours — one every 22 minutes
- 3 files over 500 lines (LauncherPanel 566, SkeinView 524, ProjectStore 496)
- ContentView has 17 @State properties (god view)
- 10 catch blocks that swallow errors silently
- 17 force unwraps
- Multiple functions over 40 lines
- DeskfloorApp.toggleLauncher is 88 lines

## What Went Wrong

### 1. Velocity over correctness

We added features faster than we verified them. The commit cadence (22 min/commit)
meant code was being written, committed, and moved on from without confirming it
actually worked at runtime. "Compiles" was treated as "works."

**Evidence:** SkeinView was written with Canvas, committed, found to be broken at
runtime (no click handling, no focus), then rewritten with List. Two commits for one
feature that should have been tested before the first commit.

**Evidence:** Fleet Jump went through 5 iterations of the SSH connection approach.
Each was committed before testing. The SSH config `RemoteCommand` conflict was
discoverable by running `ssh -G hyle` once, but we didn't check.

### 2. God objects

ContentView has 17 @State properties and controls all navigation, filtering, importing,
and view switching. It's a monolith.

DeskfloorApp is both the app entry point AND the action dispatcher AND the iTerm
integration layer AND the AppDelegate host. 175 lines doing 4 different jobs.

ProjectStore does project CRUD, git scanning, git info reading, filesystem walking,
and JSON persistence. 500 lines, one class.

### 3. Silent error swallowing

10 catch blocks catch errors and either print to console or do nothing. In a desktop
app, the user has no idea something failed. No alerts, no error state in the UI, no
retry affordance.

```swift
} catch {
    print("Failed to load projects: \(error)")  // user never sees this
}
```

### 4. Untested code paths

Zero test files. Not a single XCTest. The importers parse complex JSON formats
(ChatGPT's tree-structured mapping, Claude Code's JSONL with nested content blocks)
with no test fixtures. A malformed line in a JSONL file could crash the import
silently.

### 5. Duplicated patterns

PromptStore, ProjectStore, FrecencyTracker, SkeinStore, HistoryStore all implement
the same JSON load/save pattern independently. No shared persistence protocol.

LauncherItem and ProjectCard both compute relative dates independently.
LauncherSearch and HistoryStore both implement frecency scoring independently.

### 6. View files too large

LauncherPanel.swift (566 lines) contains the main view, the row view, the toast,
the welcome state, the error recovery state, the footer, the category header, and
helper functions. Should be 4-5 files.

SkeinView.swift (524 lines) contains SkeinView, ThreadRow, ThreadDetailView, and
TurnRow. Same problem.

### 7. Weak separation between data and presentation

The `Thread.Source` enum has `.icon` and `.label` computed properties. Data types
shouldn't know about SF Symbol names. The `SessionStatus` enum has `.color` — same
issue. This makes the data types untestable without SwiftUI imports.

### 8. No loading states for async operations

Fleet polling, git refresh, GitHub import — all async, but the UI has minimal
feedback. The git refresh now shows progress (after the fix), but fleet polling
failure is invisible. Import shows a spinner but no count of what was imported.

### 9. The launcher panel is recreated on every toggle

`AppDelegate.toggleLauncher()` creates a brand new `LauncherPanelView` on every
invocation, including fresh `ProjectStore()` and `FleetStore()` as fallbacks.
If the stores aren't wired from the App struct (which happens asynchronously via
onAppear), the launcher shows empty data.

### 10. No keyboard shortcut discoverability

The app has Cmd+1 through Cmd+5 for view modes, but these are invisible buttons
with empty labels — a hack to get keyboard shortcuts without menu items. Proper
approach: use `.commands { }` modifier or actual menu bar items.

---

## Actionable Fixes (prioritized)

### Critical (breaks user trust)

1. **Surface errors to the user.** Replace all silent catch blocks with either
   an alert, a toast, or an error state in the view. Create a shared `ErrorBanner`
   view component.

2. **Fix the launcher store wiring.** Don't create fallback stores. Assert that
   stores are set, or use a shared singleton pattern (environment object or
   dependency injection).

3. **Test the importers.** Write 3 test fixtures (one per format) and 3 unit tests.
   A malformed conversation file should not crash the app.

### High (code quality)

4. **Extract a persistence protocol.**
   ```swift
   protocol JSONPersistable: Observable {
       associatedtype Data: Codable
       var fileURL: URL { get }
       func load()
       func save()
   }
   ```

5. **Break up god objects.**
   - ContentView → ContentView + FilterState + ImportCoordinator
   - DeskfloorApp → DeskfloorApp + ActionDispatcher + ITerm
   - ProjectStore → ProjectStore + GitScanner + ProjectPersistence
   - LauncherPanel → LauncherPanelView + LauncherRow + LauncherFooter + LauncherEmptyState

6. **Separate data from presentation.** Move `.color`, `.icon`, `.label` from enum
   cases into view-side extensions:
   ```swift
   // In Models/
   enum SessionStatus: String, Codable { case live, completed, paused ... }

   // In Views/
   extension SessionStatus {
       var color: Color { ... }
       var icon: String { ... }
   }
   ```

### Medium (UX quality)

7. **Loading states for every async operation.** Create an `AsyncState<T>` enum:
   ```swift
   enum AsyncState<T> {
       case idle, loading(progress: Double?), loaded(T), failed(Error)
   }
   ```

8. **Proper keyboard shortcuts.** Use `.commands { }` in the App body for
   view mode switching. Remove the invisible button hack.

9. **Debounce search.** The launcher's `onChange(of: query)` fires on every
   keystroke. With 200+ items, add a 100ms debounce.

### Low (tech debt)

10. **Consolidate relative date formatting.** One `RelativeDate` utility, used
    everywhere.

11. **Consolidate frecency scoring.** One `FrecencyScorer` protocol, used by
    both HistoryStore and FrecencyTracker.

12. **Add .gitignore for data files.** `~/.deskfloor/` should not be tracked,
    but the app should handle a missing data directory gracefully.
