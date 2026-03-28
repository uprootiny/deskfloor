# Nielsen Usability Heuristics — Launcher Variant

## The 10 Heuristics Applied

### 1. Visibility of system status
- Show live connection indicator (green dot when fleet reachable, red when not)
- Loading spinner during search/fetch
- Result count updates in real-time as you type
- Timestamp showing when fleet data was last refreshed
- Toast confirms every action: "Connected", "Copied", "Opened"

### 2. Match between system and real world
- Use domain language: "hosts" not "servers", "sessions" not "processes"
- Alchemical sigils (🜂🜄🜁🜃) match the fleet naming convention
- "Jump to" not "Search" — matches the mental model of launching
- Relative timestamps ("2d ago") not ISO dates

### 3. User control and freedom
- Escape always dismisses, from any state
- Clear button (X) on search field
- Undo last action (Cmd+Z shows "Undo: SSH to hyle" in toast)
- Back navigation in detail views

### 4. Consistency and standards
- Same keyboard shortcuts everywhere: Enter=act, Esc=dismiss, arrows=navigate
- Same row format for all item types (icon + title + subtitle + accessory)
- Same color semantics: green=healthy, orange=warning, red=critical, blue=info

### 5. Error prevention
- Disable SSH action for unreachable hosts (grayed out, tooltip explains)
- Confirm destructive actions (if any)
- Validate search input (strip leading/trailing whitespace)
- Throttle search to prevent flicker on fast typing

### 6. Recognition rather than recall
- Show all items on empty query (don't require typing to see options)
- Category headers remind you what's available
- Action hints on selected row (SSH, ATTACH, OPEN, RUN)
- Keyboard shortcut legend in footer

### 7. Flexibility and efficiency of use
- Keyboard-only operation for power users
- Mouse/click for casual use
- Tab to jump between categories (accelerator)
- Direct type-ahead: "hy" immediately filters to hyle

### 8. Aesthetic and minimalist design
- No decorative elements — every pixel communicates
- Monospace for data, proportional for labels
- Opacity hierarchy replaces heavy borders/dividers
- Content-first: search field is 40% of the visual weight

### 9. Help users recognize, diagnose, and recover from errors
- "No results" state suggests: "Try a shorter query" or shows recent items
- Fleet offline state shows last-known data with staleness warning
- SSH failure shows the error and offers "Copy command" as fallback

### 10. Help and documentation
- Footer shows keyboard shortcuts at all times
- Tooltips on hover for every interactive element
- First-launch welcome state explains the launcher
