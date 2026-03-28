# Deskfloor Architecture

Design deliberation for a macOS 14+ SwiftUI project dashboard managing 120+ projects across multiple view modes. This document captures tradeoffs, recommendations, and rationale. No code -- just decisions.

---

## Current State

The codebase today has a single `@Observable ProjectStore` holding a flat `[Project]` array, JSON file persistence under `~/.deskfloor/projects.json`, four view modes (board, perspective, timeline, graph), drag-and-drop via string-encoded UUIDs, sidebar filtering, and GitHub import via `gh` CLI subprocess. Keyboard shortcuts use the hidden-zero-frame-button hack. No undo/redo, no multi-select, no bulk operations, no keyboard navigation beyond shortcuts.

This document addresses what needs to change to support the full feature set.

---

## 1. State Management

### 1.1 @Observable vs ObservableObject vs Redux-like Store

**Options:**

- **@Observable (Observation framework, macOS 14+):** Fine-grained property tracking. SwiftUI only re-evaluates views that read the specific properties that changed. No `@Published` boilerplate. Works with `@State` and `@Bindable`.
- **ObservableObject + @Published:** The older pattern. Coarser invalidation -- any `@Published` change triggers re-evaluation of every view that holds the object via `@ObservedObject` or `@EnvironmentObject`. Combine-based.
- **Redux-like store (TCA, custom reducer):** Single state tree, actions, reducers. Strong testability guarantees. Significant boilerplate. TCA is a heavy dependency.

**Recommendation: Stay with @Observable.** The project already uses it. For 120 items, @Observable's fine-grained tracking is a genuine performance advantage over ObservableObject -- when you change one project's status, only views reading that project re-evaluate, not every view holding the store. Redux/TCA adds substantial ceremony for a single-developer macOS app. The complexity is not justified unless you need time-travel debugging or very strict side-effect isolation, and neither is a priority here.

**Complexity cost:** Minimal. @Observable is the platform direction. The main gotcha is understanding when to use `@State` (ownership) vs `@Bindable` (borrowing) vs `@Environment` (injection).

### 1.2 Single Source of Truth for Multiple View Projections

**Problem:** Four view modes each project the same 120+ items differently (by status, by perspective, by date, by connection graph). Filtering and sorting are shared. Every view mode needs the same filtered/sorted subset, then groups it differently.

**Options:**

- **Compute projections in each view.** Simple. Risk of duplicated logic and inconsistent filtering.
- **Compute one filtered/sorted array in the store, let views group locally.** Single filtering pass, grouping is cheap.
- **Dedicated projection objects per view mode.** Over-engineered for this scale.

**Recommendation: One canonical `filteredProjects` computed property on the store, with each view doing its own grouping.** This is close to what exists today, but the filtering should move from a method call with 6 parameters (currently `store.filtered(...)`) into the store itself, with filter state living on the store. This eliminates the current problem where `ContentView` owns all filter state as `@State` and passes it around.

Concretely: move `searchText`, `selectedPerspectives`, `selectedStatuses`, `selectedEncumbranceKinds`, `handoffOnly`, `encumberedOnly`, and `sortOrder` into `ProjectStore`. Expose a single computed `var filteredProjects: [Project]` property. Views read `store.filteredProjects` and group by their column key. Because @Observable tracks property access, views that don't read `filteredProjects` won't re-evaluate when filters change.

**Complexity cost:** Low. It is a refactor that removes parameters, not one that adds abstraction.

### 1.3 Avoiding Recomputation on Every Frame

**Problem:** A computed `filteredProjects` property re-runs every time SwiftUI reads it during evaluation, which happens on any state change that could affect the reading view.

**Options:**

- **Just let it recompute.** 120 items, filtering and sorting is microseconds. Measure before optimizing.
- **Cache with manual invalidation.** Store the filtered result and recompute only when inputs change. Error-prone.
- **Derived/memoized property pattern.** Track input versions, recompute only on actual change.

**Recommendation: Let it recompute for now. 120 items is nothing.** Profile before caching. If you do need to cache later, the cleanest pattern is a private `_filteredProjectsCache` that is invalidated in `didSet` of any filter property. But do not build this until Instruments says filtering is a bottleneck, which it will not at 120 items.

**Complexity cost:** Zero if you skip it. Moderate if you add caching (manual invalidation is a bug magnet).

### 1.4 Undo/Redo

**Options:**

- **UndoManager integration.** AppKit provides this for free in every NSWindow. SwiftUI exposes it via `@Environment(\.undoManager)`. You register inverse operations. macOS gives you Cmd-Z / Cmd-Shift-Z, Edit menu integration, and undo grouping automatically.
- **Command pattern.** Define `Command` structs (MoveProject, ChangeStatus, etc.) with `execute()` and `undo()`. Push to a stack. You implement redo yourself.
- **Event sourcing.** Store a log of all mutations and derive current state by replaying. Theoretically elegant. Enormous complexity for a desktop app.

**Recommendation: UndoManager.** It is the platform-native solution. macOS has 30 years of undo infrastructure. You get menu integration, undo grouping, and "Undo Move Project" labels for free. The pattern: before mutating, register the inverse closure with `undoManager.registerUndo(withTarget:handler:)`. For bulk operations, wrap in `undoManager.beginUndoGrouping()` / `endUndoGrouping()`.

The command pattern duplicates what UndoManager already does. Event sourcing is orders of magnitude more complex than needed.

**Implementation shape:** Add an `undoManager` property to `ProjectStore` (set from the environment on appear). Each mutation method (moveProject, updateProject, deleteProject, addProject) registers its inverse before applying. This keeps undo logic co-located with mutation logic.

**Complexity cost:** Moderate. Every mutation needs an undo registration. Bulk operations need grouping. But it is well-understood, well-documented, and the platform expects it.

---

## 2. View Architecture

### 2.1 NavigationSplitView vs Custom Split Layout

**Options:**

- **NavigationSplitView.** Platform-native two-or-three-column layout. Sidebar collapse, adaptive behavior, toolbar integration. The current implementation uses this.
- **HSplitView (AppKit bridge).** Resizable split with draggable divider. More control, less SwiftUI integration.
- **Custom HStack with manual resize handles.** Full control. Full responsibility.

**Recommendation: Keep NavigationSplitView for the sidebar + detail split.** It handles sidebar collapse, proper macOS sidebar styling, and works well for the filter sidebar + main content pattern. Within the detail area, the different view modes (board, perspective, timeline, graph) are completely custom content anyway, so NavigationSplitView is not constraining.

If you later want a three-pane layout (sidebar / board / inspector), NavigationSplitView supports three columns natively. That is likely where this is heading -- clicking a project card should show an inspector panel rather than a modal sheet (sheets are disruptive for an information-dense dashboard).

**Complexity cost:** Low. Already in place. The main risk is NavigationSplitView's column width behavior, which can be quirky. If it fights you on column sizing, consider `navigationSplitViewColumnWidth(min:ideal:max:)`.

### 2.2 Flexible, Reorderable Columns

**Problem:** The board and perspective views currently hardcode columns to `Status.allCases` and `Perspective.allCases` respectively. The goal is columns that can be reordered, hidden, and that are not tied to a fixed enum.

**Options:**

- **Array of column descriptors.** Define a `ColumnDefinition` that specifies which property to group by and the column order. Persist order. Use `ForEach` over the column array.
- **Generic column view.** One `ColumnView<GroupKey>` that takes a key path and grouping function. Different view modes provide different group keys.
- **Just keep it hardcoded.** Status and Perspective are known enums. The "columns" for timeline and graph are not really columns at all.

**Recommendation: Column descriptor array for the board/perspective modes, with persisted ordering.** Define a struct that captures: display name, color, filter predicate (which projects belong in this column), and sort index. The board view becomes `ForEach(columnDefinitions) { col in ColumnView(projects: col.filter(filteredProjects)) }`. Reordering means reordering the array and persisting it.

For drag-to-reorder columns: use `.draggable` and `.dropDestination` on the column headers themselves, separate from the card drag-and-drop. This avoids conflict because column reorder operates on `ColumnDefinition` types while card drag operates on project IDs.

**Complexity cost:** Moderate. Adds a layer of indirection. Worth it only if users actually need to reorder or hide columns. Start with the hardcoded approach (as-is) and add the descriptor layer when the feature is needed.

### 2.3 LazyVGrid/LazyHGrid vs Custom Layout Protocol

**Options:**

- **ScrollView + HStack of LazyVStack columns.** This is what exists today. Each column is a LazyVStack inside a ScrollView. Simple, works.
- **LazyVGrid/LazyHGrid.** Grid layout within a single scrollable area. Good for a masonry-style board. Bad for independent per-column vertical scrolling.
- **Custom Layout protocol.** Full control over positioning. Can implement complex layouts (e.g., a timeline with overlapping cards, a force-directed graph). Significant effort.

**Recommendation: Keep the current pattern (HStack of LazyVStack columns) for board and perspective views.** It gives per-column vertical scrolling, which is essential for a kanban-style layout where columns have different heights. LazyVGrid forces all items into a single scroll region, which breaks the mental model.

For the timeline view, a custom Layout or manual Canvas drawing is appropriate since timeline layout is inherently different from grid layout.

For the graph view, use Canvas (for rendering) with manual hit testing, or consider a lightweight force-directed layout computed off the main thread and rendered with Canvas. The Layout protocol is not designed for force-directed graphs.

**Complexity cost:** Low for board/perspective (keep as-is). High for timeline and graph, but those are inherently complex views regardless of approach.

### 2.4 View Identity and ForEach Performance

**Problem:** ForEach over 120+ items needs stable identity. If identity changes, SwiftUI tears down and recreates views, which is expensive and loses state.

**Key rules:**

- **Always use `ForEach(items) { item in ... }` where items conform to Identifiable.** Never use `ForEach(items, id: \.self)` for mutable items -- if the item's Hashable value changes (any property change), SwiftUI treats it as a new item.
- **Project.id is UUID, which is stable.** This is correct. Keep it.
- **Do not use index-based ForEach.** `ForEach(0..<items.count)` has no stable identity and causes full re-renders on any array change.
- **Keep card views lightweight.** Each `ProjectCard` should read only the properties it displays. With @Observable, this means only those property accesses trigger re-evaluation.

**Recommendation:** The current approach is correct. `Project` is `Identifiable` with a stable `UUID`. `ForEach(projectsFor(status)) { project in ... }` uses the right identity. The one concern is that `projectsFor(status)` creates a new array on every evaluation, but that is just filtering, not view recreation -- SwiftUI diffs by `id`, not by array reference.

For 120 items split across 5 columns, each column has ~24 items on average. LazyVStack already virtualizes off-screen items. This will not be a performance issue.

**Complexity cost:** None. Just maintain awareness of these rules.

### 2.5 Drag-and-Drop Architecture

**Options:**

- **Transferable protocol (modern, macOS 13+).** Type-safe. Define exactly what data your drag carries. Works with `.draggable()` and `.dropDestination()`. The right approach for macOS 14+.
- **Legacy NSItemProvider / onDrag / onDrop.** More flexible for complex cases (e.g., promising multiple representations). More boilerplate.
- **String-encoded UUIDs (current approach).** Works but loses type safety. The `.draggable(project.id.uuidString)` pattern means the drop destination receives arbitrary strings and must parse UUIDs.

**Recommendation: Adopt Transferable on a wrapper type.** Define a `ProjectReference` struct conforming to `Transferable` that carries the project UUID (and optionally more metadata for cross-app drops). Use `.draggable(ProjectReference(id: project.id))` and `.dropDestination(for: ProjectReference.self)`. This is type-safe, eliminates string parsing, and is the intended pattern for macOS 14+.

For drag between columns (moving a project's status or perspective): the drop destination reads the `ProjectReference`, looks up the project, and updates the relevant field.

For multi-select drag: the `ProjectReference` could carry an array of UUIDs, or you implement selection state where dropping one selected item moves all selected items.

For column reorder (separate from card drag): use a different `Transferable` type (`ColumnReference`) so drop destinations can distinguish card drops from column drops.

**Complexity cost:** Low to moderate. Transferable conformance is straightforward. The nuance is handling multi-select drag, which requires selection state management (see next section).

---

## 3. Multi-Select and Bulk Operations

This is not in the current codebase and is architecturally significant.

**Pattern:**

- Store `var selection: Set<UUID>` on `ProjectStore` (or on a dedicated `SelectionState` observable).
- Cmd-click toggles individual selection. Shift-click extends selection range. Cmd-A selects all visible.
- Selected items get a visual highlight in all view modes.
- Bulk operations (change status, change perspective, add tag, delete) operate on `selection` set.
- Drag from a selected item drags all selected items.

**Where selection lives:** On the store, not on individual views. Selection persists across view mode switches.

**Undo for bulk operations:** Use `UndoManager.beginUndoGrouping()` / `endUndoGrouping()` to treat a bulk operation as a single undo step. The undo handler captures the prior state of all affected items.

**Complexity cost:** Moderate. Selection management, shift-click range selection (requires knowing item order), and making all view modes respect selection consistently. This is a cross-cutting concern.

---

## 4. Data Layer

### 4.1 Persistence: Codable JSON vs SwiftData vs Core Data

**Options:**

- **Codable JSON (current).** File-based. Human-readable. Trivially inspectable and editable. No query engine. Load/save is all-or-nothing.
- **SwiftData.** Apple's modern persistence. Built on Core Data. Offers lazy loading, querying, relationships. Adds schema migration machinery. Integrates with SwiftUI via `@Model` and `@Query`.
- **Core Data.** Mature. Powerful. Enormous API surface. Not recommended for new macOS 14+ projects when SwiftData exists.
- **SQLite via GRDB or similar.** Lightweight, queryable, no Apple framework coupling. Good middle ground.

**Recommendation: Stay with Codable JSON.** For 120 items with the full Project struct, the JSON file is roughly 200-400 KB. Loading it takes single-digit milliseconds. There is no query performance concern. The all-or-nothing save is fine because the data set fits in memory trivially.

JSON has real advantages for this project: human-readable backup, trivially diff-able in git, copy-able across machines, editable with any text editor, and zero framework coupling.

**Migration path:** When you outgrow JSON (unlikely at 120 items, but maybe at 1000+), the migration to SwiftData is straightforward: define `@Model` classes mirroring the current structs, read the JSON file once, insert all objects, done. Keep the JSON export ability as a backup format regardless.

**One change worth making now:** Add a `version: Int` field to the JSON envelope (wrap the array in `{ "version": 1, "projects": [...] }`). This makes future schema migrations trivial -- read the version, apply transforms.

**Complexity cost:** Minimal (stays as-is). The version envelope is a small change with high future payoff.

### 4.2 Computed Projections: Cache vs Recompute

Covered in 1.3 above. At 120 items, always recompute. The cost of filtering and sorting 120 items is measured in microseconds. Caching introduces invalidation bugs that cost hours to debug.

If specific projections are expensive (e.g., the graph view computing force-directed layout positions for all 120 nodes), compute those off the main thread and cache the result. But that is a rendering concern, not a data concern.

### 4.3 Async Import Without Blocking UI

**Problem:** The current GitHub import uses `Process()` synchronously on an async Task. `process.waitUntilExit()` blocks the calling thread. This works in a Task because Swift concurrency runs it on a cooperative thread, but it is not ideal.

**Options:**

- **Process with async notification.** Use `process.terminationHandler` instead of `waitUntilExit()`. Wrap in a `CheckedContinuation`.
- **URLSession for GitHub API directly.** Skip `gh` CLI. Use GitHub REST or GraphQL API with a personal access token. Fully async, no subprocess, better error handling.
- **Keep the `gh` subprocess approach.** It handles auth, pagination, and rate limiting. Practical.

**Recommendation: Keep `gh` CLI for now, but fix the blocking.** Wrap the process in a proper `CheckedContinuation` using `terminationHandler`. This is a small fix. Long-term, moving to URLSession with GitHub's GraphQL API gives better control (incremental loading, progress, cancellation), but the `gh` approach is pragmatic and handles auth well.

**Regardless of approach:** Import should be cancellable, should show progress, and should merge intelligently (the current "skip by name" dedup is reasonable).

**Complexity cost:** Low for the continuation fix. Moderate for a full URLSession migration.

---

## 5. Platform Integration

### 5.1 Keyboard Shortcuts

**Problem:** The current code uses invisible zero-frame buttons as a hack to register keyboard shortcuts. This is a known SwiftUI workaround, but it is fragile and semantically wrong.

**Options:**

- **`.commands { }` on Scene.** For menu bar shortcuts. This is the proper place for app-level commands (Cmd-N, Cmd-I, etc.). Already partially used in `DeskfloorApp`.
- **`.onKeyPress()` modifier (macOS 14+).** For in-view keyboard handling. This is the proper replacement for the hidden button hack. Handles arrow keys, letter keys, modifiers.
- **`keyboardShortcut()` on actual visible buttons.** When the button is visible in the toolbar, this is correct.
- **NSEvent.addLocalMonitorForEvents.** Escape hatch for complex keyboard handling. Avoid unless necessary.

**Recommendation: Use `.commands { }` for all menu-bar-level shortcuts. Use `.onKeyPress()` for view-local keyboard navigation.**

Specifically:
- Cmd-1/2/3/4 for view mode switching: put in `.commands { }` on the Scene. These are app-level commands that belong in the menu bar.
- Cmd-N for new project: `.commands { }`.
- Arrow keys for navigating between project cards: `.onKeyPress()` on the board view.
- Enter to open selected project: `.onKeyPress()` on the board view.
- Delete/Backspace for deleting selected: `.onKeyPress()` with confirmation.
- Cmd-A for select all: `.commands { }`.
- Escape to clear selection: `.onKeyPress()`.

This eliminates the hidden-button hack entirely and gives proper macOS menu bar integration where users can discover shortcuts.

**Complexity cost:** Low. Mostly a refactor. `.onKeyPress()` requires a focused view, so you need to manage focus state with `@FocusState` and `.focusable()`.

### 5.2 Focus and Keyboard Navigation

This deserves its own section because it is the hardest part of keyboard accessibility in SwiftUI.

**Pattern:**
- Make the board area `.focusable()`.
- Track `@FocusState` for which region has focus (sidebar vs board).
- Track a `focusedProjectID: UUID?` for which card has keyboard focus.
- Arrow keys move focus: left/right between columns, up/down within a column.
- Tab moves between sidebar and board area.
- The focused card gets a visible focus ring.

**The hard part:** SwiftUI's focus system is designed around text fields and controls, not custom card layouts. You will likely need to compute the navigation targets yourself (given current column layout and card positions, what is "left" of the focused card?). This is inherently complex in a multi-column layout.

**Complexity cost:** High. This is one of the most labor-intensive features on the list.

### 5.3 Menu Bar Integration

**Options:**

- **`.commands { }` modifier.** Standard approach. Add command groups for all app actions.
- **MenuBarExtra.** For a persistent menu bar icon with a dropdown. Useful for quick-access actions outside the main window.

**Recommendation: Start with `.commands { }` for a proper menu bar.** Organize into:
- File: New Project, Import from GitHub, Export JSON
- Edit: Undo, Redo, Select All, Delete
- View: Board/Perspective/Timeline/Graph, Toggle Sidebar
- Project: Change Status submenu, Change Perspective submenu, Open in GitHub

MenuBarExtra is a nice-to-have for showing active project count or quick-switching, but it is not essential.

**Complexity cost:** Low to moderate. Defining the menu structure is straightforward. Making the menu items correctly reflect the current state (e.g., disabling "Open in GitHub" when no project is selected) requires binding menu state to app state.

### 5.4 Window State Persistence

**Options:**

- **`@SceneStorage`.** Persists simple values across app launches per-scene. Works for view mode, sidebar visibility, column widths.
- **`NSWindow.setFrameAutosaveName`.** Persists window position and size. AppKit handles this automatically if you set the name.
- **UserDefaults.** Manual persistence. Full control.

**Recommendation: Use `@SceneStorage` for view-level state (selected view mode, sort order, filter state). Use `defaultSize` and `windowResizability` on the Scene for window sizing (already done). macOS automatically persists window frame position for WindowGroup scenes.**

For the sidebar collapsed state, `NavigationSplitView` with `.balanced` style persists its column visibility automatically.

**Complexity cost:** Minimal. `@SceneStorage` is a drop-in replacement for `@State` where you want persistence.

### 5.5 Opening URLs and Deep Linking

**Current approach:** `NSWorkspace.shared.open(url)`. This is correct for opening GitHub repos in the browser.

**Addition:** Support `deskfloor://` URL scheme for deep linking to specific projects (e.g., from terminal tools or Raycast). Register the scheme in Info.plist, handle with `.onOpenURL { url in ... }` on the WindowGroup.

**Complexity cost:** Low if you need it. Skip if you don't.

---

## 6. Code Organization

### 6.1 Feature-Based vs Layer-Based Module Structure

**Options:**

- **Layer-based (current).** `Models/`, `Views/`, `Utilities/`. Files grouped by what they are.
- **Feature-based.** `Board/`, `Timeline/`, `Graph/`, `Import/`, `Shared/`. Files grouped by what they do.
- **Hybrid.** Shared models at the top, feature-specific views and logic in feature folders.

**Recommendation: Hybrid, leaning feature-based as complexity grows.** The current layer-based structure is fine for 14 files. When you hit 30+ files, group by feature:

```
Sources/Deskfloor/
  App/
    DeskfloorApp.swift
    ContentView.swift
  Models/
    Project.swift
    Encumbrance.swift
    ProjectStore.swift
  Board/
    BoardView.swift
    ColumnView.swift
  Perspective/
    PerspectiveView.swift
  Timeline/
    TimelineView.swift
  Graph/
    GraphView.swift
  Detail/
    ProjectDetailSheet.swift
    ProjectCard.swift
  Import/
    GitHubImporter.swift
  Shared/
    SidebarView.swift
```

**Do not reorganize preemptively.** Reorganize when you find yourself scrolling past unrelated files to find what you need. The current flat structure has zero navigation overhead at 14 files.

**Complexity cost:** Zero now (do nothing). Moderate when reorganizing (file moves, import updates).

### 6.2 Protocol-Oriented Design for Testability

**Key protocols to define:**

- **`ProjectRepository` protocol.** `load() -> [Project]`, `save([Project])`. The store uses this instead of directly calling FileManager. Tests inject an in-memory implementation. GitHub import returns projects through the same interface.
- **`GitHubClient` protocol.** `fetchRepos(owner:) async throws -> [GitHubRepo]`. The real implementation uses `gh` CLI. Tests inject mock data. This also enables switching to URLSession later without changing the importer logic.
- **`UndoRegistrar` protocol (maybe).** Only if you need to test undo behavior without UndoManager. Probably over-abstracted.

**Recommendation: Define `ProjectRepository` and `GitHubClient` protocols.** These are the two external boundaries (file system and network). Abstracting them makes the store trivially testable and the import logic swappable. Everything else can stay concrete.

Do not protocol-abstract view models, navigation state, or filter logic. Those are not external boundaries and abstracting them adds indirection without testing benefit.

**Complexity cost:** Low. Two protocols, two production implementations, two test mocks.

### 6.3 Where Business Logic Lives

**Rules:**

- **Views contain ONLY layout, styling, and gesture handling.** No filtering, sorting, data transformation, or business rules.
- **ProjectStore contains all data mutation and query logic.** Filtering, sorting, CRUD, undo registration. This is the single authority on project state.
- **GitHubImporter is a standalone service.** It produces `[Project]` values. The store decides what to do with them (merge, replace, etc.).
- **No separate "ViewModel" layer.** With @Observable, the store IS the view model. Adding a ViewModel layer between the store and the view is pure ceremony in a single-window app. If a specific view needs derived state (e.g., the graph view needs layout positions), that computation lives in a dedicated type (e.g., `GraphLayoutEngine`), not a ViewModel.

**Recommendation: Two-layer architecture. Views and Store. Services (like GitHubImporter) are stateless utilities that the store calls.** Resist the urge to add a ViewModel layer. @Observable on the store, with computed properties for projections, gives views everything they need. When a view needs complex derived data (graph layout, timeline positioning), extract that computation into a dedicated engine type, not a ViewModel.

**Complexity cost:** None. This is the simplest layering that works.

---

## 7. Summary of Recommendations

| Decision | Recommendation | Confidence |
|---|---|---|
| Observation framework | @Observable (keep) | High |
| Filter/sort state location | Move into ProjectStore | High |
| Caching filtered results | Do not cache at 120 items | High |
| Undo/redo | UndoManager | High |
| Layout structure | NavigationSplitView (keep) | High |
| Column layout | HStack of LazyVStack (keep) | High |
| Column reorder | Defer until needed | Medium |
| Drag-and-drop | Migrate to Transferable | High |
| Persistence | Codable JSON with version envelope | High |
| GitHub import | Keep gh CLI, fix async | Medium |
| Keyboard shortcuts | .commands + .onKeyPress | High |
| Keyboard navigation | @FocusState + manual navigation | High |
| Window state | @SceneStorage | High |
| Code organization | Layer-based now, feature-based later | Medium |
| Testability | ProjectRepository + GitHubClient protocols | High |
| Architecture layers | Views + Store + Services (no ViewModel) | High |
| Multi-select | Set<UUID> on store | High |

---

## 8. Implementation Priority

Ordered by unlocking-the-most-functionality-per-effort:

1. **Move filter state into ProjectStore.** Unblocks cleaner view code across all four view modes. Small refactor, big payoff.
2. **Migrate drag-and-drop to Transferable.** Unblocks multi-select drag. Small effort.
3. **Add selection state (Set<UUID>) to store.** Unblocks multi-select, bulk operations, keyboard navigation target.
4. **Replace hidden-button keyboard shortcuts with .commands and .onKeyPress.** Unblocks proper menu bar and keyboard navigation.
5. **Add UndoManager integration.** Every mutation method gets an undo registration. Medium effort, high user value.
6. **Add JSON version envelope.** Five minutes of work. Insurance for every future migration.
7. **Extract ProjectRepository and GitHubClient protocols.** Unblocks testing.
8. **Keyboard navigation in board view.** High effort, high polish.
9. **Inspector pane (replace sheet with third NavigationSplitView column).** High information density improvement.
10. **Column reorder and customization.** Only when users request it.
