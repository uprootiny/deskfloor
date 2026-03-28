# Deskfloor Session 2 — Self-Reflection

## What happened

In roughly 6 hours, we went from a 1,737-line SwiftUI scaffolding to a 3,500+ line
application with 28 source files, 3 experiment branches, 5 design documents, and 7
handoff files. The app imports 200 GitHub repos, shows them in 5 view modes, has a
global hotkey launcher, fleet status, conversation archaeology (Skein), multi-select
with dispatch to Claude Code, and SSH jumping to remote hosts.

## What went right

1. **The visual design.** The info-dense, monospace-data, layered-opacity aesthetic
   was validated immediately and has held up across every new view. The user called
   it "very, very good, expert, masterful." This is a real signal — the design
   language is coherent and works.

2. **Fleet bar → iTerm SSH.** After 5 iterations of dead ends, the SSH jumping
   actually works. The user confirmed it: "clicking karlsruhe gives me a functional
   iTerm with SSH and tmux running on karlsruhe." A real, tested, useful feature.

3. **The Skein architecture.** The data model (Thread, Turn, ToolLoop, Artifact,
   Splice, Excerpt, Composition) is clean and comprehensive. The Claude Code
   importer works and found real data. The first-principles UX design document
   is thorough and actionable.

4. **Sheet performance fix.** Switching from `.sheet(isPresented:)` to
   `.sheet(item:)` made project cards open instantly. The user confirmed this.

## What went wrong

1. **Velocity addiction.** 11 commits in 4 hours, one every 22 minutes. Most were
   not tested at runtime. The Canvas-based SkeinView was committed, found broken,
   and rewritten. Fleet Jump went through 5 iterations. The ray-so workflow took
   3 tries. Each "fix" commit was another untested change.

2. **Feature breadth over depth.** We built 5 view modes, a launcher, fleet
   integration, NLP engine, prompt store, history store, frecency tracker, Skein
   architecture, two importers, and a dispatch panel. Most of them don't actually
   work reliably. The user had to tell me: "the underlying logic is not implemented
   in code."

3. **Ignoring the user's real needs.** The user wanted to dispatch agents, shape
   prompts, arrange contexts, multi-select cards, and ensure CI/CD runs. We built
   graph views and typography experiments instead. The dispatch panel should have
   been built in hour 1, not hour 6.

4. **God objects.** ContentView has 17 @State properties. ProjectStore does 5 jobs.
   LauncherPanel is 566 lines. These are the direct result of adding features
   without restructuring.

5. **Silent failures.** 10 catch blocks swallow errors. The user has no idea when
   something fails. This is disrespectful of the user's time.

## What the user actually needs

The user said it most clearly through their rapid-fire messages:
- "dispatch an agent"
- "shape a prompt"
- "arrange a context"
- "attach validation harnesses"
- "ensure GitHub CI/CD healthy runs"
- "grab logs and feedback"
- "get an agent to iterate on engineering"
- "profile runs"
- "all of these should be repeatable reliable LLM-agent-powered plots"
- "and Deskfloor should naturally arrange and offer them"
- "and actually work"
- "and watch over itself"

This is not a project dashboard. This is a **cognitive operations center** that:
1. Knows what you have (repos, conversations, agents, infrastructure)
2. Knows what state it's in (CI status, git dirty, fleet health)
3. Lets you compose and dispatch work (select, prompt, send to Claude Code)
4. Monitors the results (logs, CI runs, agent outputs)
5. Feeds results back (update project status, link to conversations)

## What to do next

The constitution says: one thing at a time, tested before commit.

The single most impactful thing is to verify that the three features just built
(view switching, multi-select, dispatch) actually work when the user clicks them.
If they do, the app crosses from "viewer" to "orchestrator."

After that, every new feature should be an action, not a visualization:
- Dispatch selected projects to Claude Code (just built)
- Run `gh run list` for selected projects and show CI status (action, not decoration)
- Run `git status` for local projects and show dirty/clean (action, not decoration)
- Auto-import conversations on Skein view open (just built, needs testing)

The beautiful views can wait. The actions are what make the app useful.
