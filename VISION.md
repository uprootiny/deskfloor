# Deskfloor Vision

## What it is

A mission control for a solo operator's constellation of projects, servers, and agents.

You point at a project. You say "go." An agent session spins up on the right server,
in the right repo, with the right context, working on the right roadmap, committing,
pushing, and reporting back.

## What it is NOT

- Not a dashboard (passive)
- Not a kanban board (manual)
- Not a code editor (wrong level of abstraction)
- Not a chat interface (too narrow)

## The core interaction

```
1. SEE    — your projects, their state, what needs attention
2. POINT  — click a project, or Cmd+Click several
3. RUN    — one click: agent session launches with full context
4. WATCH  — progress streams back, status updates, commits appear
5. STEER  — redirect, stop, adjust scope while it runs
```

## What "RUN" means concretely

Click a project card → right-click → "Run Agent Session":

1. Deskfloor reads the project's repo, description, language, roadmap, recent commits
2. Constructs a context prompt: "You are working on {project}. Here is the state: {git status, CI status, open issues}. The roadmap says: {roadmap}. Continue."
3. Opens iTerm → SSH to the right host (hyle for infra, finml for ML, local for Swift)
4. Runs `claude --context /tmp/deskfloor-context-{project}.md` in the repo directory
5. The agent works: reads code, makes changes, commits, pushes
6. Deskfloor polls: git log, CI status, AgentSlack messages → updates the card in real time

## The mesh

Multiple agent sessions can run simultaneously:
- Agent on hyle fixing AgentSlack serve.py
- Agent on finml training a model
- Agent locally improving Deskfloor itself
- Agent on hub2 deploying a service

Deskfloor shows all of them. You steer from one seat.

## What the card should show

Not a form. Not a wall of text. A **control surface**:

```
┌─────────────────────────────────────────┐
│ coggy                    ● Active   Ops │
│ Cognitive core           Clojure        │
│ main · 3 dirty · 2d ago                 │
│─────────────────────────────────────────│
│ CI: ● green (2h ago)  Issues: 3 open   │
│ Agent: idle            Last run: 1d ago │
│─────────────────────────────────────────│
│ [▶ Run]  [SSH]  [GitHub]  [Logs]        │
└─────────────────────────────────────────┘
```

The [▶ Run] button is the whole point.
