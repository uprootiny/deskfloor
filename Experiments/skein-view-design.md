# Skein View — Interaction & Visual Design Specification

## Purpose

The Skein View is a temporal topology of all LLM conversations. It answers:
- When did I work on what?
- Which sessions are alive, dead, or abandoned?
- Where did approaches converge or diverge?
- What can I pick back up?

It is NOT a chat log viewer. It's an **operations timeline for cognitive work**.

---

## Layout Architecture

### Three Zones (top to bottom)

```
┌─────────────────────────────────────────────────────────────────┐
│ RULER    │  Mar 26         │  Mar 27         │  Mar 28          │
├──────────┼─────────────────┴─────────────────┴──────────────────┤
│          │                                                      │
│ LANES    │  ══════════  ═══════  ════════════════                │
│          │       ═══════════════                                 │
│          │  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░                 │
│          │  ·· ·· ··    ····  ··      ···· ····                  │
│          │                                                      │
├──────────┼──────────────────────────────────────────────────────┤
│ DETAIL   │  [Selected thread detail / turn preview]             │
└──────────┴──────────────────────────────────────────────────────┘
```

**Ruler** (fixed, 32px tall): Time axis. Shows date labels, hour ticks when zoomed in,
month labels when zoomed out. Today marker as a vertical red hairline.

**Lanes** (scrollable, fills remaining space): Swim lanes for threads. Each source type
gets a lane group. Within each group, threads are stacked vertically by start time.

**Detail strip** (collapsible, 200px default): Shows info about the hovered or selected
thread. Collapses to 0px when nothing is selected. Expands to show turns when a thread
is clicked.

### Lane Groups (top to bottom)

1. **Claude Code** — main conversations (thick bars)
2. **Claude.ai / ChatGPT** — web conversations (medium bars)
3. **AgentSlack** — continuous channel feed (thin translucent bar)
4. **Subagents** — short burst dots

Each group has a 16px label on the left margin. Groups are separated by a 1px rule.

---

## Visual Language

### Thread Bars

Each thread is a horizontal rectangle:

```
┌──────────────────────────────┐
│ ███████████████████████████  │  Live: solid, rounded corners
└──────────────────────────────┘

┌──────────────────────────────┐
│ ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  │  Completed: solid, slightly dimmer
└──────────────────────────────┘

┌──────────────────────────────┐
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░  │  Paused: translucent fill
└──────────────────────────────┘

┌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┐
╎ ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ ╎  Abandoned: dashed outline, no fill
└╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘

┌──────────────────────────────┐
│ ████░░░░████░░░░████░░░░███ │  Crashed: hatched/striped fill
└──────────────────────────────┘

┌──────────────────────────────┐
│ ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  │  Hypothetical: dotted, purple-tinted
└──────────────────────────────┘
```

### Bar Dimensions

- Height: 24px for main conversations, 16px for web, 8px for agent, 4px for subagent
- Min width: 4px (even very short sessions are visible)
- Corner radius: 4px
- Gap between bars in same group: 3px
- Gap between groups: 12px

### Color Encoding

Primary: thread color if user-assigned, otherwise derived from source:
- Claude Code: `rgb(0.35, 0.65, 0.95)` (sky blue)
- Claude.ai: `rgb(0.85, 0.55, 0.25)` (warm orange)
- ChatGPT: `rgb(0.4, 0.8, 0.5)` (mint green)
- AgentSlack: `rgb(0.6, 0.5, 0.8)` (lavender)
- Subagents: `white @ 30%`

Secondary (overlaid): status modifies opacity and pattern:
- Live: 100% opacity
- Completed: 80% opacity
- Paused: 50% opacity
- Abandoned: 30% opacity, dashed border
- Crashed: 60% opacity, diagonal stripe overlay
- Hypothetical: 40% opacity, dotted border

### Turn Density Markers

Inside each bar, small vertical ticks mark individual turns:

```
███│█│████│██│█████│███│██████│██
   ↑     ↑          ↑
   turn  turn       turn (user message)
```

- Tick height: 60% of bar height
- Tick width: 1px
- Tick color: white @ 20% (barely visible, creates texture)
- Bookmarked turns: tick is gold, full height
- Dead-end turns: tick is red
- Breakthrough turns: tick is green, full height, slightly wider (2px)

### Splices (Cross-Thread Connections)

Curved lines connecting turns in different threads:

```
═══════╤═══════════        Thread A
       │
       ╰──────────╮
                   │
══════════════════╧════    Thread B
```

- Line style: 1px, white @ 15%, bezier curve
- Hover: line brightens to white @ 50%, shows label tooltip
- Click: selects both connected turns

### Today Marker

A vertical line across all lanes at the current time position:
- Color: red @ 40%
- Width: 1px
- Label: "now" in 8pt monospace at the ruler

---

## Interaction Design

### Zoom & Pan

**Horizontal zoom** (time axis):
- Scroll wheel / trackpad pinch: zoom in/out
- Zoom levels: year → month → week → day → hour
- At hour level, turn ticks become individually clickable

**Horizontal pan**:
- Two-finger scroll / drag on ruler
- Shift+scroll wheel

**Vertical scroll**:
- Regular scroll to see more lanes

### Zoom Level Detail

| Zoom | Time range visible | Bar labels | Turn ticks | Ruler labels |
|------|-------------------|------------|------------|--------------|
| Year | 12 months | None | None | "2025", "2026" |
| Quarter | 3 months | Thread title if bar > 60px | None | "Jan", "Feb", "Mar" |
| Month | 30 days | Thread title | None | "Mar 1", "Mar 8" |
| Week | 7 days | Title + turn count | Visible | "Mon", "Tue" |
| Day | 24 hours | Title + topics | Clickable | "00:00", "06:00" |
| Hour | 60 minutes | Full detail | Expanded | "14:00", "14:15" |

### Selection

**Single click on bar**: Select thread → detail strip shows thread info.
**Double click on bar**: Open Session Inspector (overlay or sheet).
**Click on turn tick** (zoomed in): Select turn → detail strip shows turn content.
**Shift+click**: Add to selection (multi-select threads).
**Cmd+click**: Toggle selection.

### Context Menu (right-click on thread bar)

```
┌──────────────────────────────┐
│ Open Session Inspector       │
│ ─────────────────────────── │
│ Set Status ▸  ● Live         │
│              ● Completed     │
│              ○ Paused        │
│              ○ Abandoned     │
│              ○ Crashed       │
│ ─────────────────────────── │
│ Set Color  ▸  🔴🟠🟡🟢🔵🟣 │
│ Add Tag...                   │
│ Link to Project...           │
│ ─────────────────────────── │
│ Extract All Prompts → Loom   │
│ Extract All Artifacts → Loom │
│ ─────────────────────────── │
│ Create Splice from Here      │
│ ─────────────────────────── │
│ Archive                      │
│ Delete                       │
└──────────────────────────────┘
```

### Drag Interactions

**Drag thread bar → Loom View**: Extract all turns as excerpts into the loom.
**Drag turn tick → Shuttle View**: Add that turn's content to the active composition.
**Drag from one thread to another**: Create a splice between the closest turns.

### Keyboard

| Key | Action |
|-----|--------|
| ←/→ | Move selection to previous/next thread |
| ↑/↓ | Move selection to thread above/below |
| Enter | Open Session Inspector for selected thread |
| Space | Quick preview (expand detail strip) |
| B | Toggle bookmark on selected turn |
| D | Toggle dead-end on selected turn |
| G | Toggle breakthrough on selected turn |
| T | Add tag to selected thread |
| S | Cycle status of selected thread |
| E | Extract selected turn → Loom |
| C | Add selected turn → Shuttle (active composition) |
| / | Focus search/filter |
| Cmd+1-7 | Switch view modes |
| Cmd++ / Cmd+- | Zoom in/out |

---

## Detail Strip (Bottom Panel)

### Thread Selected (nothing expanded)

```
┌─────────────────────────────────────────────────────────────────┐
│ ● bootstrap & discovery      Claude Code      Mar 26, 14:22    │
│   132 turns · 847 tool calls · 23 artifacts · 5 topics         │
│   Topics: setup, nix, github, fleet, BespokeSynth              │
│   Status: ● Completed                         [Open Inspector] │
└─────────────────────────────────────────────────────────────────┘
```

### Turn Selected (zoomed in)

```
┌─────────────────────────────────────────────────────────────────┐
│ Turn 47 of 132 · Mar 26, 18:40 · Thread: bootstrap & discovery │
│                                                                 │
│ YOU: "cool now let's go through github cli setup, auth, and     │
│       triage our repos to pick several that we should totally   │
│       have locally on a fresh machine"                          │
│                                                                 │
│ CLAUDE: [4 tool calls: Bash, Bash, Bash, Read] → installed gh, │
│         authenticated, listed 168 repos, classified into tiers  │
│                                                                 │
│ [☆ Bookmark] [✕ Dead End] [✓ Breakthrough] [→ Loom] [→ Shuttle]│
└─────────────────────────────────────────────────────────────────┘
```

---

## Filter / Search

A compact filter bar above the lanes:

```
┌────────────────────────────────────────────────────────────────┐
│ 🔍 [filter text]  Source: [All ▾]  Status: [All ▾]  [14 of 79]│
└────────────────────────────────────────────────────────────────┘
```

- Text filter: matches thread title, topics, tags
- Source dropdown: Claude Code, Claude.ai, ChatGPT, AgentSlack, All
- Status dropdown: Live, Completed, Paused, Abandoned, All
- Count shows filtered/total

Filtering fades out non-matching threads (opacity → 10%) rather than hiding them,
preserving spatial context.

---

## Empty States

### No threads imported yet

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│              ╭─────────────────────────────────╮                │
│              │   No conversation threads yet    │                │
│              │                                  │                │
│              │   [Import Claude Code]           │                │
│              │   [Import ChatGPT Export]        │                │
│              │   [Import Claude.ai Export]      │                │
│              ╰─────────────────────────────────╯                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Import in progress

```
┌─────────────────────────────────────────────────────────────────┐
│   Importing Claude Code conversations...                        │
│   ████████████████████░░░░░  47 of 79 files                    │
│   Found: 2,847 turns, 156 tool loops, 89 artifacts             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Performance Considerations

- **79 threads × ~50 turns avg = ~4,000 turns**. All fit in memory.
- **Bar rendering**: Use Canvas (not individual SwiftUI views) for the lanes.
  Drawing 100 rectangles on a Canvas is trivial; 100 VStacks is not.
- **Turn ticks**: Only render when zoomed to week level or closer.
  At month+ level, bars are solid colored rectangles.
- **Detail strip**: Only renders content for the selected thread/turn.
  Not all 4,000 turns are in the view hierarchy.
- **Splices**: Draw on a separate overlay Canvas to avoid recomputing
  bar positions when splices change.

---

## Implementation Structure

```swift
struct SkeinView: View {
    // State
    @State var skein: SkeinStore
    @State var store: ProjectStore         // for project linking
    @State private var selectedThreadID: UUID?
    @State private var selectedTurnID: UUID?
    @State private var zoomLevel: ZoomLevel = .week
    @State private var scrollOffset: CGFloat = 0
    @State private var filterText: String = ""
    @State private var filterSource: Thread.Source?
    @State private var filterStatus: SessionStatus?
    @State private var detailExpanded: Bool = false

    enum ZoomLevel: Double, CaseIterable {
        case year = 0.01      // 1px per day
        case quarter = 0.05
        case month = 0.15
        case week = 0.6
        case day = 4.0        // 4px per hour = 96px per day
        case hour = 24.0      // 24px per hour

        var pixelsPerHour: CGFloat { CGFloat(rawValue) }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider().opacity(0.2)
            GeometryReader { geo in
                VStack(spacing: 0) {
                    timeRuler(width: geo.size.width)
                    threadLanes(size: geo.size)
                    if detailExpanded { detailStrip }
                }
            }
        }
    }
}
```

### Sub-components

1. **TimeRuler** — Canvas drawing date labels and tick marks
2. **ThreadLaneGroup** — Canvas drawing all bars for one source type
3. **SpliceOverlay** — Canvas drawing bezier curves between threads
4. **DetailStrip** — SwiftUI view for selected thread/turn info
5. **FilterBar** — HStack with TextField + Pickers
6. **ThreadContextMenu** — context menu builder

### Canvas vs SwiftUI Decision

The **lanes** use `Canvas` for performance:
- 79+ rectangles with opacity/pattern variations
- Turn ticks are 1px lines (potentially thousands)
- Splices are bezier curves
- All of this needs to re-render on zoom/pan

The **detail strip** uses SwiftUI:
- Only shows one thread/turn at a time
- Has interactive elements (buttons, toggles)
- Benefits from SwiftUI's built-in accessibility

The **filter bar** and **ruler** use SwiftUI:
- Simple HStack layouts
- Standard controls (TextField, Picker)

---

## Animation

### Zoom
- Time axis scales with spring animation (0.2s, response 0.3)
- Bars grow/shrink horizontally
- Turn ticks fade in at week zoom level (opacity transition, 0.15s)

### Selection
- Selected bar: white outline fades in (0.1s)
- Detail strip: slides up from bottom (0.15s, ease out)
- Deselection: reverse

### Filter
- Non-matching threads: opacity fades to 10% (0.2s)
- Matching threads: remain at full opacity
- Count badge updates immediately

### Import
- New threads appear with a slide-in from right (0.3s, spring)
- Progress bar uses standard ProgressView

---

## Typography in the Skein View

| Element | Font | Size | Weight | Design |
|---------|------|------|--------|--------|
| Ruler dates | SF Mono | 9pt | regular | monospaced |
| Ruler hours | SF Mono | 8pt | regular | monospaced |
| Group label | System | 10pt | semibold | default |
| Bar label (title) | System | 10pt | medium | default |
| Bar label (topics) | SF Mono | 8pt | regular | monospaced |
| Turn count | SF Mono | 8pt | regular | monospaced |
| Detail thread title | System | 14pt | semibold | default |
| Detail stats | SF Mono | 11pt | regular | monospaced |
| Detail topics | SF Mono | 10pt | regular | monospaced |
| Detail turn content | System | 12pt | regular | default |
| Filter text | System | 12pt | regular | default |
| Filter count | SF Mono | 10pt | medium | monospaced |
| "now" label | SF Mono | 8pt | bold | monospaced |

---

## Color Summary

| Element | Color |
|---------|-------|
| Background | rgb(0.06, 0.06, 0.08) — darkest |
| Ruler background | rgb(0.08, 0.08, 0.10) |
| Ruler text | white @ 30% |
| Ruler today line | red @ 40% |
| Group label | white @ 25% |
| Group separator | white @ 6% |
| Bar (Claude Code) | rgb(0.35, 0.65, 0.95) |
| Bar (Claude.ai) | rgb(0.85, 0.55, 0.25) |
| Bar (ChatGPT) | rgb(0.4, 0.8, 0.5) |
| Bar (AgentSlack) | rgb(0.6, 0.5, 0.8) |
| Bar (Subagent) | white @ 30% |
| Bar selected outline | white @ 60%, 1.5px |
| Turn tick normal | white @ 15% |
| Turn tick bookmarked | gold @ 70% |
| Turn tick dead-end | red @ 60% |
| Turn tick breakthrough | green @ 80% |
| Splice line | white @ 12% |
| Splice hover | white @ 40% |
| Detail background | rgb(0.08, 0.08, 0.10) |
| Detail border top | white @ 8% |
| Filter background | rgb(0.07, 0.07, 0.09) |
| Filter count badge | white @ 6% bg, white @ 40% text |
