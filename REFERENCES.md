# Deskfloor Architectural References

Research notes for building a macOS SwiftUI project dashboard app.

---

## 1. Open-Source macOS SwiftUI Apps with Kanban / Board UIs

### SwiftUI Sample Kanban Board
- **Repo:** https://github.com/abdulkarimkhaan/SwiftUI-Sample-Kanban-Board
- **What it is:** Minimal kanban board using SwiftUI's `draggable()` and `dropDestination()` APIs.
- **Worth borrowing:** Shows the simplest viable drag-between-columns pattern using modern SwiftUI APIs (no NSItemProvider).
- **Avoid:** Very minimal -- no persistence, no undo, no real architecture. Treat as a snippet, not a codebase reference.

### Kanbanwa
- **Repo:** https://github.com/jwamin/Kanbanwa
- **What it is:** SwiftUI Lifecycle kanban board prototype.
- **Worth borrowing:** Pure SwiftUI lifecycle (no AppDelegate), lightweight column model.
- **Avoid:** Prototype-quality; unlikely to have robust drag-drop edge-case handling.

### Kanban Code (langwatch)
- **Repo:** https://github.com/langwatch/kanban-code
- **What it is:** macOS kanban app with GitHub issue integration and drag-and-drop.
- **Worth borrowing:** Real-world kanban with external data source integration; AGPLv3.
- **Avoid:** AGPL license is viral -- do not copy code directly. Study patterns only.

---

## 2. Well-Architected SwiftUI Codebases

### isowords (Point-Free)
- **Repo:** https://github.com/pointfreeco/isowords
- **What it is:** Full game (iOS) built entirely with The Composable Architecture (TCA) and SwiftUI. 86+ Swift modules, includes both client and server.
- **Architectural highlights:**
  - Single source of truth `Store` with composed `Reducer`s.
  - Extreme modularity -- every feature is its own SPM module with isolated previews.
  - Comprehensive test suite using TCA's `TestStore`.
- **Worth borrowing:** Module-per-feature SPM layout; snapshot testing patterns; how to compose large reducers from small ones.
- **Avoid:** TCA is heavy and opinionated. The full redux-style indirection may be overkill for a dashboard app. Consider borrowing the *modularity* without the *framework*.

### The Composable Architecture (TCA)
- **Repo:** https://github.com/pointfreeco/swift-composable-architecture
- **What it is:** The framework itself. Provides composition, testing, and ergonomics for SwiftUI apps.
- **Worth borrowing:** `Dependency` injection system; effect cancellation patterns; `@Shared` state for cross-feature communication.
- **Avoid:** Steep learning curve; frequent API churn between major versions; can feel over-engineered for simpler apps.

### Clean Architecture SwiftUI (Alexey Naumov)
- **Repo:** https://github.com/nalexn/clean-architecture-swiftui
- **Blog:** https://nalexn.github.io/clean-architecture-swiftui/
- **What it is:** Sample app demonstrating Clean Architecture with SwiftUI, SwiftData, networking, dependency injection, and unit testing.
- **Worth borrowing:** Clear separation of Interactors / Repositories / Views; shows how to test SwiftUI apps without TCA; lightweight DI approach.
- **Avoid:** iOS-focused; would need adaptation for macOS idioms (multiple windows, menu bar, etc.).

### IceCubesApp (Thomas Ricouard)
- **Repo:** https://github.com/Dimillian/IceCubesApp
- **What it is:** Full-featured SwiftUI Mastodon client (iOS/macOS). One of the most polished open-source SwiftUI apps.
- **Architectural highlights:**
  - Barebones MVVM -- no redux, no TCA. Proves you do not need a framework.
  - Multi-package SPM layout split by domain/feature. Almost no code in the app target itself.
  - `@StateObject` for view models, `@EnvironmentObject` for shared services (account, theme, preferences).
  - Bodega (SQLite) for timeline caching; UserDefaults for scroll position persistence.
- **Worth borrowing:** Package-per-domain layout; lightweight MVVM without a framework; EnvironmentObject-based theming/preferences; how to handle multi-account state.
- **Avoid:** Heavy use of `@EnvironmentObject` can make dependency graphs implicit and hard to trace in larger apps. Consider `@Environment` with custom keys or explicit injection instead.

---

## 3. Information-Dense macOS Apps (Open Source)

### CodeEdit
- **Repo:** https://github.com/CodeEditApp/CodeEdit
- **What it is:** Native macOS code editor, written in Swift/SwiftUI + AppKit. Aims to replace VS Code with a native experience.
- **Architectural highlights:**
  - Hybrid SwiftUI + AppKit -- uses AppKit where SwiftUI falls short (text editing, custom window chrome).
  - Modular sub-packages: `CodeEditSourceEditor` (tree-sitter powered), separate UI components.
  - Multi-pane layout with sidebar, editor area, inspector, terminal.
- **Worth borrowing:** How to do a multi-pane IDE-style layout in SwiftUI on macOS; when and how to drop to AppKit; modular editor component extraction.
- **Avoid:** Very large codebase; ongoing heavy development. Use as a reference for specific patterns (e.g., split views, file tree) rather than trying to understand the whole thing.

### Cork
- **Repo:** https://github.com/buresdv/Cork
- **What it is:** Fast Homebrew GUI for macOS, written in SwiftUI with some AppKit.
- **Worth borrowing:** Good example of a focused macOS utility with dense tabular data display; uses Tuist + Mise for build tooling; menu bar integration.
- **Avoid:** Custom license (not fully open-source for redistribution). Study, do not copy.

### eul
- **Repo:** https://github.com/gao-sun/eul
- **What it is:** macOS status monitoring app written in SwiftUI. Displays CPU, memory, battery, network, disk, fan in compact menu bar widgets.
- **Worth borrowing:** Information-dense compact views; real-time data display patterns in SwiftUI; menu bar popover architecture.
- **Avoid:** May be unmaintained; check last commit date.

### Stats
- **Repo:** https://github.com/exelban/stats
- **What it is:** macOS system monitor in the menu bar. Very popular (20k+ stars).
- **Worth borrowing:** Extremely information-dense UI in constrained space; modular widget/module system; how to display live-updating metrics.
- **Avoid:** Primarily AppKit, not SwiftUI. Useful for UI density inspiration, less so for SwiftUI patterns.

### Ice
- **Repo:** https://github.com/jordanbaird/Ice
- **What it is:** Menu bar manager for macOS. Drag items between visible/hidden sections.
- **Worth borrowing:** Drag-and-drop between zones (visible vs. hidden); macOS 14+ system API usage; focused single-purpose SwiftUI macOS app architecture.
- **Avoid:** Narrow scope (menu bar only). Good for drag-drop zone patterns, not for dashboard layout.

### Swiftcord
- **Repo:** https://github.com/SwiftcordApp/Swiftcord
- **What it is:** Native Discord client for macOS, 100% SwiftUI.
- **Worth borrowing:** Multi-column chat layout (server list + channel list + messages + member list) is structurally similar to a kanban/dashboard; shows how to handle complex nested navigation in SwiftUI on macOS.
- **Avoid:** Alpha-quality; GPL v3 license.

---

## 4. SwiftUI Drag-and-Drop Best Practices

### Core APIs (modern, preferred)
- `.draggable()` + `.dropDestination()` -- type-safe, works with `Transferable` protocol.
- For custom model types: conform to `Codable` + `Transferable`, implement `transferRepresentation` using `CodableRepresentation`.
- Register a custom `UTType` in Info.plist conforming to `public.data`.

### DropDelegate (lower-level, more control)
- Use `DropDelegate` protocol with `.onDrop(of:delegate:)` for fine-grained control over drop behavior (hover effects, insertion points, validation).
- Combine with `.onDrag { NSItemProvider(object: ...) }` for the drag source.

### macOS-Specific Gotchas
- `Transferable` with only a `FileRepresentation` does not work for Finder drops. Add a `ProxyRepresentation` returning the URL below the `FileRepresentation` as a workaround. (Source: https://nonstrict.eu/blog/2023/transferable-drag-drop-fails-with-only-FileRepresentation/)
- Drop zones need minimum dimensions or SwiftUI will collapse them too small.
- `String`, `Image`, `Data`, `URL` already conform to `Transferable` out of the box.

### Reordering Items
- `List` + `ForEach` + `.onMove(perform:)` is the simplest path for reorderable lists.
- For `LazyVGrid` / `LazyHGrid` / `LazyVStack` / `LazyHStack`, `.onMove` is NOT available. Must use `.onDrag()` + `.onDrop()` with a custom `DropDelegate` and manual state management.
- Third-party: https://github.com/globulus/swiftui-reorderable-foreach -- generic `ReorderableForEach` that plugs into any layout container.

### Reordering Columns (not just items within columns)
- No built-in SwiftUI API for this. Must be implemented manually:
  - Model columns as an ordered array.
  - Make each column view draggable (column ID as the transfer payload).
  - Use `DropDelegate` on each column to detect hover and reorder the array.
  - Animate with `withAnimation { columns.move(fromOffsets:toOffset:) }`.

### Key References
- Apple docs: https://developer.apple.com/documentation/swiftui/drag-and-drop
- Hacking with Swift: https://www.hackingwithswift.com/quick-start/swiftui/how-to-support-drag-and-drop-in-swiftui
- Daniel Saidi (lazy grids): https://danielsaidi.com/blog/2023/08/30/enabling-drag-reordering-in-swiftui-lazy-grids-and-stacks
- Eclectic Light (macOS specifics): https://eclecticlight.co/2024/05/21/swiftui-on-macos-drag-and-drop-and-more/

---

## 5. SwiftUI `Layout` Protocol for Custom Column Arrangements

### Overview
- Introduced in WWDC22. Two required methods: `sizeThatFits(proposal:subviews:cache:)` and `placeSubviews(in:proposal:subviews:cache:)`.
- Works like a custom `HStack` / `VStack` -- you control exact positioning of every subview.
- Supports automatic animation when switching between layouts using `AnyLayout`.

### For a Kanban Board
- A custom `Layout` can arrange columns horizontally with configurable widths and spacing.
- Can respond to `ProposedViewSize` to implement responsive behavior (collapse columns when narrow).
- The `Layout` protocol handles *positioning* but not *interaction*. Drag-and-drop reordering of columns must be handled separately (see section 4 above).

### Key References
- WWDC22 session: https://developer.apple.com/videos/play/wwdc2022/10056/
- Apple docs: https://developer.apple.com/documentation/swiftui/composing-custom-layouts-with-swiftui
- Hacking with Swift: https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-a-custom-layout-using-the-layout-protocol
- Deep dive: https://medium.com/@wesleymatlock/custom-layouts-in-swiftui-a-deep-dive-into-the-layout-protocol-5edc691cd4fb

### Three-Column Editor Pattern (not NavigationSplitView)
- Michael Sena's post on three-column editors in SwiftUI on macOS: https://msena.com/posts/three-column-swiftui-macos/
- `NavigationSplitView` is too rigid for a kanban -- it enforces sidebar/detail semantics and auto-collapses.
- Better approach: `HStack` of column views with custom `Layout`, or `ScrollView(.horizontal)` containing a `LazyHStack` of column views.

---

## 6. SwiftUI + UndoManager Patterns for macOS

### Environment Access
```
@Environment(\.undoManager) var undoManager
```
Available in any SwiftUI view within a window scene.

### UndoProvider Pattern
- Create a wrapper that intercepts `Binding` writes and registers undo actions.
- When registering an undo, register another undo inside the undo block -- this is how the system creates redo.
- Editable text inputs (TextField, TextEditor) already handle their own undo/redo automatically.

### macOS Advantages
- Undo/Redo menu items and keyboard shortcuts (Cmd+Z / Cmd+Shift+Z) are provided automatically.
- The system hooks into `UndoManager` for the Edit menu without additional work.

### Document-Based Apps
- `ReferenceFileDocument` uses `UndoManager` events to detect document dirtiness and trigger auto-save.
- If building a document-based dashboard, register all mutations through `UndoManager` to get free dirty-state tracking.

### Key References
- Nil Coalescing blog: https://nilcoalescing.com/blog/HandlingUndoAndRedoInSwiftUI/
- Hacking with Swift forums: https://www.hackingwithswift.com/forums/macos/swiftui-app-life-cycle-undo-redo-and-menu-bar-items/7771
- Apple docs: https://developer.apple.com/documentation/swiftui/environmentvalues/undomanager
- GitHub gist (UndoProvider): https://gist.github.com/kkla320/cfa2f1943d7f37a7f90afe68310f9b76
- Kodeco tutorial (value types): https://www.kodeco.com/5229-undomanager-tutorial-how-to-implement-with-swift-value-types

---

## 7. Curated Lists for Further Exploration

These meta-repositories catalog many more open-source macOS/Swift apps:

- https://github.com/serhii-londar/open-source-mac-os-apps
- https://github.com/jaywcjlove/awesome-swift-macos-apps
- https://github.com/open-saas-directory/awesome-native-macosx-apps
- https://github.com/donarb/swiftui-macos (SwiftUI-specific macOS resources)

---

## Summary: Recommended Starting Points

| Goal | Best Reference |
|------|---------------|
| Overall architecture | IceCubesApp (lightweight MVVM, multi-package SPM) |
| Kanban drag-drop | SwiftUI-Sample-Kanban-Board + Daniel Saidi's lazy grid reordering |
| Information-dense macOS UI | CodeEdit (multi-pane), eul/Stats (compact data) |
| Custom column layout | Layout protocol (WWDC22) + Michael Sena's three-column post |
| Undo/redo | Nil Coalescing UndoProvider pattern |
| Modular architecture without a framework | IceCubesApp (MVVM + packages) |
| Modular architecture with a framework | isowords + TCA |
| Column reordering | Manual: ordered array + DropDelegate + withAnimation |
