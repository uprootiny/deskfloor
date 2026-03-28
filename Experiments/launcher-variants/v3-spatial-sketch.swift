// v3 Spatial Launcher — Design Sketch
// Not compiled, just a design exploration
//
// Concept: Instead of a flat list, the launcher shows a spatial view
// with the fleet as a mini constellation and projects as a card cloud.
//
// The search field filters and re-arranges the spatial layout,
// zooming into relevant clusters.

/*
┌────────────────────────────────────────────────────────────┐
│ 🔍 [search field]                                          │
├────────────────────────────────────────────────────────────┤
│                                                            │
│   ┌─────────────────────┐  ┌────────────────────────────┐ │
│   │    FLEET             │  │     PROJECTS               │ │
│   │                      │  │                            │ │
│   │    🜂 hyle ●●●       │  │  ┌──────┐ ┌──────┐       │ │
│   │      ╱    ╲          │  │  │coggy │ │solvu │       │ │
│   │  🜄 finml  🜁 hub2   │  │  │ 1d   │ │ 2d   │       │ │
│   │      ╲    ╱          │  │  └──────┘ └──────┘       │ │
│   │    🜃 karl            │  │  ┌──────┐ ┌──────┐       │ │
│   │                      │  │  │hyle  │ │mycla │       │ │
│   │  load ████░░  1.0    │  │  │ 9d   │ │ 2d   │       │ │
│   │  disk ██████░ 75%    │  │  └──────┘ └──────┘       │ │
│   │  cl   ████████ 8     │  │                            │ │
│   └─────────────────────┘  └────────────────────────────┘ │
│                                                            │
│  Enter: act on selection   Tab: switch pane   Esc: close  │
└────────────────────────────────────────────────────────────┘

When typing "hyle", the fleet pane zooms to hyle showing its tmux sessions.
When typing "coggy", the project pane highlights coggy and shows its detail.
*/

// Key SwiftUI patterns needed:
// - Canvas or Path for the constellation lines
// - matchedGeometryEffect for zoom transitions
// - Two-pane layout with Tab switching focus
// - DragGesture for panning the spatial view
