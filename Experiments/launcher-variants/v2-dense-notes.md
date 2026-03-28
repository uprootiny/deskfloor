# Launcher v2: Information-Dense

The current production launcher. Key design decisions:

## Layout
- 640px wide floating panel with vibrancy material
- Search bar at top: 20pt light font, "Jump to..." placeholder
- Results grouped by category with monospace headers + separator lines
- Each row: colored icon box (28x28) + title + monospace subtitle + action hint badge
- Footer: keyboard shortcut keys in pills + fleet status dot

## Keyboard
- Arrow up/down: move selection (with ScrollViewReader auto-scroll)
- Tab: jump to next category group
- Enter: execute action with toast feedback
- Escape: dismiss

## Visual Hierarchy
1. Search query (largest, lightest weight)
2. Selected row (white background, semibold title, action hint visible)
3. Row titles (13pt regular)
4. Subtitles (10pt monospace, 40% white)
5. Category headers (9pt bold monospace, 25% white, with separator line)
6. Footer keys (9pt monospace in pill badges)

## Information Density
- Host rows show inline metric pills: load (green/orange/red), disk% (green/orange), claude count (blue)
- Action hints appear only on the selected row: SSH, ATTACH, OPEN, RUN
- Result count badge appears in search bar when filtering
- Toast feedback on action execution (green bar, 0.3s delay before dismissing)

## What Works
- Fast visual scanning — icons + color coding + inline metrics
- Keyboard-first — never need the mouse
- Zero-latency feel — onChange resets selection, ScrollViewReader follows

## What To Explore Next
- v3: Spatial layout — hosts as a mini fleet constellation, not a list
- v4: Conversational — type "ssh to the coggy desk on hyle" as natural language
- Frecency integration — most-used items float to top of empty query
- Inline preview — hover or arrow-right to see project details without opening
