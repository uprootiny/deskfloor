# Obvious Uses We're Missing

Things Deskfloor should obviously do but doesn't yet.

## Immediate (code exists but isn't wired)

1. **Multi-select cards → batch action.** Select 5 projects, right-click → "Set all to Paused", "Tag all as legacy", or "Dispatch agent with context from these." The data model supports it, the UI doesn't.

2. **Local git status on project cards.** We know which repos are cloned locally (~/Nissan/*). Cards should show: dirty/clean, commits ahead/behind, last local commit message. One `git status` per cloned repo.

3. **Open in terminal from card.** Click a project → "Open in iTerm" should cd to the local clone and attach/create a tmux session. We have the iTerm AppleScript pattern. Just wire it.

4. **Drag card from dashboard to launcher.** Drag a project card out of the board and drop it into the launcher search to populate the search with that project's name. Or drag to iTerm to cd there.

5. **Cmd+K everywhere.** The launcher (Ctrl+Space) should also work as Cmd+K inside the dashboard — same search, same actions, contextual to what you're looking at.

## Data enrichment (needs new fetches)

6. **Real commit counts.** `gh api repos/uprootiny/{name}/commits?per_page=1` with Link header parsing gives actual commit count. Or `gh api repos/{owner}/{name} --jq .size` for rough size.

7. **Open PRs / issues.** `gh pr list -R {repo}` and `gh issue list -R {repo}`. Show PR count badge on cards. Surface in launcher as searchable items.

8. **CI status.** `gh run list -R {repo} --limit 1`. Green/red/yellow dot on project cards. "Last build: 2h ago, green" in detail sheet.

9. **Dependency graph.** Parse Package.swift / Cargo.toml / project.clj in cloned repos to discover actual dependency relationships. Replace the weak name-prefix heuristic.

10. **README preview.** Fetch README.md for each repo. Show as markdown in the detail sheet. NLPEngine can extract key topics.

## Workflow automation

11. **Batch clone.** Select repos that aren't cloned → "Clone all to ~/Nissan" button. Uses `gh repo clone` in parallel.

12. **Agent dispatch from selection.** Select 3 project cards → "Ask Claude about these" → constructs a prompt with the projects' names, descriptions, languages, status, connections, and opens Claude Code or copies to clipboard.

13. **Fleet action from dashboard.** The fleet bar shows hosts. Clicking a host should offer: SSH, view tmux sessions, check disk, pull git on all repos on that host.

14. **Scheduled refresh.** Auto-reimport from GitHub every 24h. Detect repos that changed status (new commits, archived, forked). Show "3 repos updated since yesterday" notification.

15. **Export to AgentSlack.** Post a project status digest to #general or #code-review. "Here are the 5 most active repos this week, 3 repos that went stale."

## Intelligence

16. **Topic clustering.** Use NLPEngine to cluster projects by description similarity, not just the hardcoded perspective heuristic. Show as a force-directed graph with real semantic distances.

17. **Stale detection.** Projects with no activity in 90 days that are still marked "Active" → surface as "Needs attention" in sidebar.

18. **Bus factor analysis.** Which projects have only 1 contributor? Which have no CI? Which have no README? Show as a "health" score per project.

19. **Cross-repo search.** Type a function name or error message in the launcher → search across all cloned repos via ripgrep. Show file:line results.

20. **Conversation context.** Link projects to Claude conversation history (from corpora-bridge). "Last discussed 2 days ago, topics: build workflow, CI fix."
