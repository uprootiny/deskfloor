# Deskfloor Type Scale

## Current Scale (v2)

| Element | Size | Weight | Design | Opacity |
|---------|------|--------|--------|---------|
| Search query | 20pt | light | default | 1.0 |
| Row title | 13pt | regular/semibold | default | 1.0 |
| Row subtitle | 10pt | regular | monospaced | 0.4 |
| Category header | 9pt | bold | monospaced | 0.25 |
| Metric pills | 9pt | medium | monospaced | 0.8 |
| Action hints | 9pt | medium | monospaced | 0.3 |
| Footer keys | 9pt | medium | monospaced | varies |
| Dashboard card title | 12pt | semibold | monospaced | 1.0 |
| Dashboard card desc | 10pt | regular | default | 0.6 |
| Dashboard card meta | 11pt | regular | monospaced | 0.4 |
| Sidebar section | 9pt | semibold | default | 0.3 |
| Sidebar filter | 11pt | regular | default | 0.4-1.0 |

## Observations

- Monospaced is used for: subtitles, metrics, counts, timestamps, language tags, category headers
- Default is used for: titles, descriptions, search query, sidebar labels
- The split works well — monospace = data, proportional = names/descriptions
- Smallest readable size is 9pt — used for tertiary info only

## Fonts to Try

### JetBrains Mono
- Better coding ligatures
- Slightly wider than SF Mono
- Good for the monospaced elements

### IBM Plex Mono + IBM Plex Sans
- Matches the dissemblage.art aesthetic
- Already used on raindesk.dev
- Would create visual coherence between Mac app and web surfaces

### Experiment: All-Monospace
- Everything in SF Mono or JetBrains Mono
- Grid-aligned, terminal aesthetic
- Might be too much for long descriptions

### Experiment: Hebrew Support
- User has Hebrew locale
- SF Pro has Hebrew support
- Consider bidirectional text in search results
