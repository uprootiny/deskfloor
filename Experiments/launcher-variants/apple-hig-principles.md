# Apple HIG Launcher Variant

## Principles Applied

1. **Familiar patterns** — Use standard macOS idioms: NSSearchField appearance, sidebar
   source list style, standard selection highlight, system accent color
2. **Vibrancy and materials** — .sidebar material for the results, .titleBar for header
3. **System fonts at system sizes** — No custom sizes. Use .headline, .body, .caption, .footnote
4. **Generous spacing** — Apple recommends 8pt grid. Comfortable padding, not cramped
5. **SF Symbols everywhere** — No custom icons, use Apple's symbol set consistently
6. **Standard controls** — Toggle, Picker, Button with .bordered style. No custom chrome
7. **Accessibility first** — Dynamic type support, VoiceOver labels, reduce motion respect
8. **Focus ring** — Standard macOS focus ring on selected items
9. **Sidebar + detail pattern** — NavigationSplitView where appropriate
10. **System colors** — .accent, .secondary, .tertiary. Not custom RGB

## Key Differences from v2

| Aspect | v2 (current) | Apple HIG |
|--------|-------------|-----------|
| Font | Custom sizes (20/13/10/9pt) | .title3/.body/.caption/.caption2 |
| Colors | Custom RGB, white opacity | System .primary/.secondary/.tertiary |
| Selection | White 7% background | System accent color highlight |
| Icons | Colored icon boxes | SF Symbols, no background |
| Spacing | Tight (7pt vertical) | 10-12pt vertical, 8pt grid |
| Material | .ultraThickMaterial | .sidebar for results, .bar for header |
| Metrics | Custom colored pills | Standard text, system colors |
| Footer | Custom key pills | Standard toolbar or touch bar style |
