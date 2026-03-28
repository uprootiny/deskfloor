# Remote Session Control — Techniques and Experiments

## The Goal

From Deskfloor on the Mac, control LLM agent sessions (claude, gemini, codex)
running in tmux on remote servers. Read their output, send commands, approve
permission prompts, steer their work.

## Techniques to Try

### 1. tmux send-keys (current, crude)

**How:** `ssh host "tmux send-keys -t session 'text' Enter"`
**Pros:** Works immediately, no setup, any tmux session
**Cons:** Blind — can't see output without separate capture. One-way. No real-time. Shell escaping is fragile.
**Score: 3/10** — functional but terrible UX

### 2. tmux capture-pane polling

**How:** Poll `tmux capture-pane -t session -p` every N seconds
**Pros:** See what's on screen. Detect prompts by pattern matching.
**Cons:** Polling latency (1-5s). Misses fast-scrolling output. Screen-sized buffer only.
**Combine with #1:** Capture to detect "Allow once?" → send-keys "2".
**Score: 5/10** — usable for slow interactive sessions

### 3. tmux control mode (-C)

**How:** `ssh host "tmux -C attach -t session"` streams structured events
**Format:** `%output <pane> <data>`, `%session-changed`, `%window-add`
**Pros:** Real-time output stream. Machine-parseable. Bidirectional.
**Cons:** Complex protocol to implement. SSH connection stays open. Need to handle reconnection.
**Score: 7/10** — the proper way if we invest in a parser

### 4. Script + pipe via tmux pipe-pane

**How:** `tmux pipe-pane -t session "cat >> /tmp/session-log.txt"` then tail -f the log
**Pros:** Full output capture to file. Can tail remotely.
**Cons:** Needs setup per session. Log file grows unbounded. No input direction.
**Combine with #1:** Pipe-pane for output + send-keys for input.
**Score: 6/10** — good for logging, not for interaction

### 5. WebSocket bridge on the server

**How:** Run a small bridge process that exposes tmux session I/O over WebSocket
**Pros:** Real-time bidirectional. Deskfloor connects directly. Multiple clients.
**Cons:** Needs a service deployed on each server. Security implications.
**Existing tools:** gotty, ttyd, wetty, xterm.js with node backend
**Score: 8/10** — best UX but most setup

### 6. SSH with PTY forwarding

**How:** Open a persistent SSH connection with PTY, attach to tmux, forward I/O
**Pros:** Native terminal experience. Full input/output.
**Cons:** Basically building a terminal emulator in Deskfloor. Complex.
**Existing:** libssh2 (already in iTerm2's build). Could embed.
**Score: 6/10** — overkill if we just want to steer agents

### 7. Agent-level API (the right long-term answer)

**How:** Instead of controlling the terminal, have agents expose an HTTP/SSE API
**Format:** POST /send {message} → SSE stream of responses
**Pros:** Clean separation. No terminal scraping. Structured data.
**Cons:** Requires modifying agent runners. Doesn't work for vanilla claude CLI.
**For Gemini:** Already has `--output json` mode
**For Claude:** Has `--print` mode for non-interactive, but no API mode
**Score: 9/10 for the future** — but requires agent cooperation

## Experiment Plan

### Experiment A: Automated permission approver (techniques 1+2)
1. SSH to nabla
2. Start `tmux pipe-pane -t main "cat >> /tmp/gemini-output.log"`
3. Tail the log from Mac: `ssh nabla "tail -f /tmp/gemini-output.log"`
4. Pattern-match for "Allow once" → `tmux send-keys -t main '2' Enter`
5. Record: How reliable? How fast? What breaks?

### Experiment B: tmux control mode parser (technique 3)
1. Write a Swift function that opens `ssh host "tmux -C attach -t session"`
2. Parse the `%output` events in real-time
3. Display in Deskfloor as a live-updating text view
4. Send input via the same connection
5. Record: Latency, reliability, reconnection behavior

### Experiment C: ttyd bridge (technique 5)
1. Install ttyd on nabla: `apt install ttyd` or `nix-env -iA nixpkgs.ttyd`
2. Run: `ttyd -p 7681 tmux attach -t main`
3. Open in Deskfloor via WKWebView
4. Record: Full terminal experience? Latency? Security?

### Experiment D: Agent API wrapper (technique 7)
1. Write a thin wrapper: `claude --print "$prompt" | tee /tmp/claude-output.txt`
2. Expose via a simple HTTP endpoint on the server
3. Deskfloor POSTs context, GETs output
4. Record: How much agent functionality is lost in non-interactive mode?

## What Deskfloor Should Show

```
┌─────────────────────────────────────────────────────────────┐
│ REMOTE SESSIONS                                             │
├──────────────┬──────────────────────────────────────────────┤
│              │                                              │
│ ● nabla:main │  ✦ I'll check the OS details to determine   │
│   Gemini 3   │    the best way to install GitHub CLI...     │
│   solvulator │                                              │
│              │  ⏺ Shell: sudo apt update && sudo apt        │
│ ○ hyle:main  │    install gh -y                             │
│   (idle)     │                                              │
│              │  [Allow] [Deny] [Send message]               │
│ ○ hub2:main  │                                              │
│   (idle)     │                                              │
│              │                                              │
└──────────────┴──────────────────────────────────────────────┘
```

Left: session list with status (active/idle/blocked).
Right: live output from selected session.
Bottom: input field + action buttons.
