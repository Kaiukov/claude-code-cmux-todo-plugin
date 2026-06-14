---
name: orchestrator-onboard
description: Auto-switch to orchestrator mode for the current project + first-run preflight.
---

# orchestrator-onboard

Start here.

1. Adopt orchestrator mode for THIS repo. You are now the orchestrator for THIS repo.
   - The host repo is `git rev-parse --show-toplevel` of the cwd, or `$ORCH_REPO_ROOT` if set.
   - All worktrees and run-state target the host repo, not the plugin; this stays portable across projects.
2. First-run preflight: fast, fail-fast, no deep re-checking. Show each check on one line with ✓/✗.
   - ✓/✗ cwd is inside a git repo (`git rev-parse --show-toplevel`)
   - ✓/✗ required CLIs present: `tmux`, `pi`, `jq`, `git` (`command -v`)
   - ✓/✗ `.tasks/orchestrator/` will live in the host repo (create on first dispatch)
   - ✓/✗ no orphan active run for the issue/role about to be dispatched (`bin/orch-status`)
   - ✓/✗ role prompt exists for the chosen role (`prompts/pi/roles/<role>.md`)
   - If any check is ✗, tell the user the single fix and stop.
3. Read board status and show active runs with `bin/orch-status`.
4. State the V1 rules:
   - GitHub is the source of truth.
   - tmux is transport, not authority.
   - pi is the worker runtime.
   - workers commit locally and never push.
   - the orchestrator never merges without explicit user OK.
5. Pick the next step and hand off to `bin/orch-dispatch` if a ready issue exists.

Keep it short and action-first.
