# What Actually Matters

The app needs to DO things, not just SHOW things.

## What works now
- Import 200 repos from GitHub ✓
- Display them in a board ✓
- Click card → detail sheet (now instant) ✓
- Fleet bar → SSH to host via iTerm ✓
- Ctrl+Space launcher (when it works) ✓

## What's broken or missing (user's words)
- Can't switch between views (freezes)
- Can't multi-select cards
- Can't dispatch an agent
- Can't shape a prompt
- Can't arrange a context
- Edit form is "moronic" — nobody fills out forms for 200 projects

## The Three Actions That Would Make This Useful

### 1. Multi-select → Context → Dispatch
Select 3 project cards. Press Cmd+D (Dispatch). A panel appears showing:
- The selected projects' names, descriptions, languages, status
- A text field for your prompt
- A "Dispatch to Claude Code" button that copies everything and opens iTerm

This is 50 lines of code and transforms the app from a viewer into an orchestrator.

### 2. View Switching Must Be Instant
The toolbar buttons need to work. The freeze is because switching from Board
(200 LazyVStack cards across 4 columns) to another view forces a full teardown
and rebuild. Fix: keep all views in a TabView or ZStack and just toggle visibility.

### 3. Click Card → Read-Only Summary (Not Edit Form)
Replace the edit sheet with a compact popover showing:
- Name, description, language, status (read-only, well-formatted)
- Git info if local (branch, dirty files, last commit)
- Quick actions: [Open in iTerm] [Open on GitHub] [Change Status ▾] [Add to Selection]
- No forms. No pickers. No typing.

## Priority
1. Fix view switching (ZStack toggle)
2. Multi-select with Cmd+Click
3. Dispatch panel (Cmd+D)
4. Replace edit sheet with read-only summary + quick actions
