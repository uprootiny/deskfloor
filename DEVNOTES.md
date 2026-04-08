# Deskfloor Dev Notes — What Worked, What Didn't, What Keeps Tripping Us Up

## Swift/SwiftUI Pitfalls (memo to self)

### 1. `.sheet(isPresented:)` vs `.sheet(item:)`
**Problem:** `.sheet(isPresented:)` with `if let` inside causes the entire parent view to
re-evaluate when the sheet opens. With 200 project cards, this freezes the UI for seconds.
**Fix:** Use `.sheet(item: $selectedProject)` — SwiftUI only evaluates the sheet content, not the parent.
**Lesson:** Always use `item:` for sheets that depend on optional selection state.

### 2. `@State var fleet: FleetStore = FleetStore()` creates orphan instances
**Problem:** When a view declares `@State var fleet = FleetStore()`, it creates its OWN
instance separate from the one in the App struct. Two pollers, two data sets, nothing shared.
**Fix:** Pass stores from the App struct: `ContentView(store: store, fleet: fleet)`.
**Lesson:** Never default-initialize `@State` for shared data. Pass it explicitly.

### 3. Codesigning after binary copy
**Problem:** Copying a new binary into a .app bundle invalidates the code signature. macOS
kills the process with `SIGKILL (Code Signature Invalid)` on the next code page access
(often triggered by a timer callback).
**Fix:** `codesign --force --sign -` after every binary copy. Put it in `build.sh`.
**Lesson:** The crash doesn't happen immediately — it happens when macOS checks a code page
that wasn't loaded at launch. Timer callbacks are common triggers.

### 4. SSH `RemoteCommand` conflicts with command-line commands
**Problem:** SSH config has `RemoteCommand tmux new -A -s main` for fleet hosts. When you
also pass `-t 'tmux attach ...'`, SSH rejects it: "Cannot execute command-line and remote command."
**Fix:** Use `-o RemoteCommand=none` to override when passing explicit commands.
**Lesson:** Always check `ssh -G host` to see the resolved config before assuming args work.

### 5. Raycast sandbox blocks `exec`
**Problem:** Raycast extensions can't use `child_process.exec` for SSH or AppleScript.
**Fix:** Use `@raycast/utils`'s `runAppleScript` or `@raycast/api`'s `open()`.
But `runAppleScript` blocks until the script finishes (SSH = forever → timeout).
**Final fix:** Fire-and-forget `exec("osascript ...")` with `child.unref()`.
**Lesson:** Raycast extensions live in a sandbox. Test every system interaction.

### 6. SwiftUI `TextEditor` focus in `HSplitView`
**Problem:** TextEditor inside HSplitView doesn't receive first-responder, so Cmd+V doesn't work.
**Workaround:** Add `.onKeyPress` handler that intercepts Cmd+V and reads NSPasteboard manually.
**Lesson:** SwiftUI focus management is unreliable in complex layouts. Test paste explicitly.

### 7. Local `.package(path:)` breaks CI
**Problem:** `Package.swift` with `.package(path: "../nlp-engine")` works locally but fails in
GitHub Actions because the sibling directory doesn't exist in the checkout.
**Fix:** Use `.package(url: "https://github.com/uprootiny/nlp-engine.git", branch: "main")`.
**Lesson:** Local path dependencies are for development only. CI needs URL references.

### 8. Canvas rendering breaks hit-testing
**Problem:** SwiftUI `Canvas` draws arbitrary shapes but provides no gesture/focus support.
You can't click on a drawn rectangle — there's no view hierarchy to hit-test against.
**Fix:** Use regular SwiftUI views (List, LazyVStack) for interactive content. Canvas only for
pure visualization with no interaction.
**Lesson:** Canvas is for drawing, not for UI. If users need to click it, use views.

### 9. `process.waitUntilExit()` blocks the main thread
**Problem:** `GitHubImporter` and `ProjectStore.refreshGitInfo()` use `Process` to run git
commands. `waitUntilExit()` blocks whatever thread it's on.
**Fix:** Wrap in `Task.detached(priority: .utility)`. Update UI on `@MainActor`.
**Lesson:** Never run `Process` on the main thread. Always detach.

### 10. Too many `@State` properties = god object
**Problem:** ContentView had 19 `@State` properties managing everything — view mode, filters,
selection, import state, dispatch state, error state.
**Fix:** Extract into focused sub-views (done in later session).
**Lesson:** If a view has more than 5-6 `@State` properties, it's doing too much.

## Architecture Decisions That Held Up

1. **Five subsystems (Atlas, Helm, Skein, Loom, Watchtower)** — clear separation of concerns.
2. **FleetStore polling AgentSlack** — real data, not mocked. Works from day one.
3. **iTerm AppleScript for SSH** — reliable once we got the pattern right.
4. **Project import from `gh` CLI** — 200 repos in one command.
5. **Dark theme with layered opacity** — validated by user, consistent across views.
6. **NLPEngine as a separate package** — reusable, independently testable.

## Architecture Decisions That Caused Pain

1. **Canvas-based SkeinView** — rewritten to List after it couldn't handle clicks.
2. **Launcher as SwiftUI Window** — replaced with NSPanel after focus issues.
3. **Python NLP engine** — deleted after user said "no Python". Rewrote in Swift.
4. **Raycast extensions as the launcher** — superseded by native Deskfloor launcher.
5. **ContentView as god object** — accumulated 19 @State before decomposition.

## What We Keep Tripping Over

1. **Testing features only by compiling, not by clicking.** "Builds" ≠ "works."
2. **Adding new views before existing ones are solid.** 7 view modes, several half-baked.
3. **Dispatch not actually reaching claude.** Fixed 3 times, still fragile.
4. **Silent error swallowing.** Fixed in later session but caused hours of mystery bugs.
5. **Scope creep within sessions.** Started as "fix the launcher," ended with fleet probing,
   gemini session hijacking, BespokeSynth UI, and consultancy repositioning.
