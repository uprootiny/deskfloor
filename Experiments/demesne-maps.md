# Demesne Maps — Truthful Views of the Software Estate

## What maps does the operator need?

### Map 1: Fleet Topology (the physical layer)

```
                         ┌─────────────┐
                         │  Mac (local) │
                         │  M4, Sequoia │
                         │  Deskfloor   │
                         └──────┬───────┘
                                │ SSH
                ┌───────────────┼───────────────┐
                │               │               │
         ┌──────▼──────┐ ┌─────▼─────┐ ┌──────▼──────┐
         │  🜂 hyle     │ │ 🜁 hub2    │ │ 🜃 karlsruhe │
         │  12G · 75%  │ │ 12G · 67% │ │ 6G  · 83%   │
         │  17 tmux    │ │ 8 tmux    │ │ 4 tmux      │
         │  9 claude   │ │ 4 claude  │ │ 0 claude    │
         │  PRIMARY    │ │ secondary │ │ dormant     │
         └──────┬──────┘ └───────────┘ └─────────────┘
                │
         ┌──────▼──────┐
         │  🜄 finml    │     ┌──────────────┐ ┌──────────┐
         │  12G · 89%  │     │ ☁ gcp1       │ │ ∇ nabla  │
         │  3 tmux     │     │ 31G · 93% 🔴 │ │ 4G · 20% │
         │  LOCKUP ⚠  │     │ 7 tmux       │ │ 3 tmux   │
         └─────────────┘     │ Grafana      │ │ gemini   │
                              └──────────────┘ └──────────┘
```

This should be an **interactive view** in Deskfloor. Click a host → see its
services, sessions, and health. Right-click → SSH, Jack In, Run Agent.

### Map 2: Service Mesh (the process layer)

```
hyle:80 nginx ──→ hyle:8080 raindesk
                  hyle:8421 coggy
                  hyle:9400 agentslack
                  hyle:9900 orchestra
                  hyle:19090 prometheus
                  hyle:19300 grafana

External:
  dissemblage.art ──→ hyle:80
  raindesk.dev ──→ hyle:80
  observatory.raindesk.dev ──→ hyle:80
  corpora.hyperstitious.org ──→ 🔴 wrong cert
  atlas.raindesk.dev ──→ 🔴 no response
  honeycomb.raindesk.dev ──→ 🔴 no response
```

Each service shows: status (up/down/degraded), port, last response time.
Click → opens the URL or SSHes to the host.

### Map 3: Project Constellation (the code layer)

Not the flat board — a **spatial graph** showing project relationships:

```
          coggy ←──── agentslack
            │              │
            ▼              ▼
        orchestra    flux
            │
            ▼
        raindesk ←── observatory
            │
            ▼
     dissemblage ←── umbra
```

With:
- Node size = activity (commit frequency)
- Node color = perspective
- Edge thickness = connection strength
- Node glow = has running agent
- Click → project detail. Right-click → Run Agent.

### Map 4: Agent Sessions (the work layer)

```
ACTIVE AGENTS                    STATUS         HOST      SINCE
────────────────────────────────────────────────────────────────
claude · deskfloor               coding         local     2h ago
claude · coggy                   idle           hyle      1d ago
gemini · solvulator              blocked (sudo) nabla     1h ago
claude · 01-ops-anchor           idle           hyle      3d ago
```

With real-time status from fleet polling. Each row has:
[Attach] [View Output] [Stop] [Dispatch New]

### Map 5: Conversation Archive (the memory layer)

The Skein view — but positioned as a map of "what you've discussed":

```
Mar 26          Mar 27          Mar 28
─────────────────────────────────────
█████████       ████████        ████████████████  bootstrap→discovery→deskfloor
                █████████                         fleet probing
                        ████████████████████████  agent dispatch experiments
                                ████  ████  ████  subagents
```

### Map 6: CI/CD Pipeline (the build layer)

```
REPO              LAST BUILD    STATUS   ARTIFACTS
──────────────────────────────────────────────────
BespokeSynth      2h ago        ✅ ✅    .app (2 targets)
ManicAI           2d ago        ✅✅✅   .app .dmg .zip (3 targets)
Flycut/Conchis    2d ago        ✅       .app .dmg .zip
ray-so            1d ago        ✅       standalone
iTerm2            1d ago        ✅       .app.zip
coggy             —             no CI    —
deskfloor         —             no CI    —
```

Each row: [Trigger Build] [Download Artifact] [View Logs]

### Map 7: Attention Dashboard (the "what needs doing" layer)

Not a map — a **sorted list of everything that needs action**:

```
🔴 CRITICAL
  gcp1 disk 93% (742MB free)                    [SSH] [Clean]
  finml CPU4 soft lockup                         [SSH] [Kill PID]

⚠ WARNING
  finml disk 89%                                 [SSH] [Clean]
  nabla gemini 45% CPU                           [SSH] [Check]
  5 domains broken/down                          [Fix nginx]
  Coggy budget overdrawn                         [Nudge]

ℹ INFO
  3 repos need upstream merge                    [Merge]
  deskfloor has 17 @State in ContentView         [Refactor]
  0 test files across all projects               [Write tests]
  Prometheus has 0 alert rules                   [Configure]
```

## How These Maps Fit Into Deskfloor

Each map is a **view mode** in the toolbar, extending the current set:

```
Current: [Board] [Perspective] [Timeline] [Graph] [Skein] [Loom]

Proposed: [Board] [Perspective] [Timeline] [Graph] [Skein] [Loom]
          [Fleet] [Services] [Agents] [CI] [Attention]
```

That's 11 view modes — too many for a flat toolbar. Group them:

```
Projects: [Board] [Perspective] [Timeline] [Graph]
Ops:      [Fleet] [Services] [CI] [Agents]
Intel:    [Skein] [Loom] [Attention]
```

Three tabs in the toolbar, each with sub-views. Or: a command palette
(the launcher) where you type the view name.

## What to Build First

The **Attention view** — because it answers "what do I do right now?" which
is the question every operator asks when they sit down. It requires the
DataBus to feed it, but even a static version (manually populated from
what we know) would be more useful than another visualization.

Second: **Fleet topology** — interactive visual of the 6 hosts with live
metrics, because that's where the fires are.

Third: **CI dashboard** — because knowing which builds are green/red
changes what you work on.
