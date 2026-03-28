# Progressive Disclosure in the Launcher

## Concept

The launcher shows different levels of detail based on how you interact:

### Level 1: Scan (default)
One line per item. Icon + title + key metric. This is what you see on launch.

### Level 2: Peek (arrow keys pause on an item for 0.5s, or press right arrow)
Expand the selected row to show:
- Full description (not truncated)
- All tags
- Last 3 actions taken on this item
- For hosts: all tmux sessions inline
- For projects: language, commit count, last commit message

### Level 3: Detail (Cmd+Enter or double-click)
Open a detail popover attached to the row:
- Full project card with all metadata
- For hosts: live terminal preview (via SSH + script)
- For projects: file tree, recent commits, open PRs
- Editable fields (tags, status, notes)

## Implementation

```
Arrow Down/Up → Level 1 (move selection, no expansion)
Arrow Right   → Level 2 (expand selected item inline)
Arrow Left    → Level 1 (collapse back)
Enter         → Execute primary action
Cmd+Enter     → Level 3 (detail popover)
Space         → Quick preview (like Finder Quick Look)
```

## SwiftUI Pattern

Use `DisclosureGroup` or a custom `@State var expandedID: String?`:

```swift
ForEach(items) { item in
    VStack(spacing: 0) {
        LauncherRow(item: item, isSelected: ...)
        if expandedID == item.id {
            LauncherRowDetail(item: item)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
```

The detail panel could use `.matchedGeometryEffect` for smooth expansion.
