# Deskfloor Design Experiments

Design explorations and UI/UX variants. Each directory contains standalone SwiftUI views
that can be swapped into the main app for testing.

## launcher-variants/
Different launcher panel designs:
- `v1-minimal.swift` — Current: simple list, category headers
- `v2-dense.swift` — Information-dense: inline metrics, action hints, keyboard shortcut badges
- `v3-spatial.swift` — Spatial: hosts as a mini constellation, projects as cards
- `v4-conversational.swift` — Conversational: natural language input, AI-powered intent parsing

## typography/
Font and type scale experiments:
- Monospace-first vs proportional-first
- JetBrains Mono vs SF Mono vs IBM Plex Mono
- Compact vs comfortable line heights
- Hebrew + English mixed-script rendering

## color-studies/
Palette and theming:
- Dark mode variants (pure black, warm dark, cool dark)
- Accent colors per perspective
- Status color semantics
- Fleet health gradients (green→amber→red)

## interaction-patterns/
Novel interaction experiments:
- Drag-drop between launcher and dashboard
- Gesture-based category switching
- Inline editing in launcher results
- Progressive disclosure (summary → detail on hover)
