# cmux-todo-board

Claude Code plugin that bridges GitHub Issues into a local task board,
mirrors ready tasks into Claude's built-in task list, and dispatches work
through cmux panes.

**Status:** MVP (one-directional: GitHub Issues → local board → task list).
Sync-back to GitHub is future work.

## Installation

```bash
# Clone the repo
git clone <repo-url> cmux-todo-board

# Load plugin in Claude Code
claude --plugin-dir ./cmux-todo-board

# Or, if already running:
/reload-plugins
```

## Skills

| Skill               | Description                                                |
|---------------------|------------------------------------------------------------|
| `/board-init`       | Initialize a repo with canonical board status labels. Run once per repo before board-pull. |
| `/board-pull`       | Fetch GitHub issues and render the local board.            |
| `/board-plan`       | Mirror `ready` tasks into Claude's built-in task list.     |
| `/board-run-ready`  | Dispatch ready tasks to cmux panes for parallel execution. |
| `/board`            | Show the board flow and operating rules.                   |

## Workflow

```
GitHub Issues  --board-pull-->  .tasks/board.json  --board-plan-->  Claude task list
                                                              |
                                                              v
                                             board-run-ready --> cmux panes
```

0. **`/board-init --repo owner/repo`** (run once) — create canonical status labels.
1. **`/board-pull --repo owner/repo`** — fetch issues, render board.
2. Review `TODO.md` to see all tasks grouped by status.
3. **`/board-plan`** — create Claude tasks for all `ready` items.
4. **`/board-run-ready`** — dispatch tasks into cmux panes.

## Verification

```bash
# Run the board-render tests
bash tests/test_board_render.sh

# Run the union/dedup logic tests
bash tests/test_board_pull_union.sh

# Validate plugin structure (if claude CLI available)
claude plugin validate .
```

## Scope

- **MVP (Phase 1):** Pull issues → render board → plan → dispatch.
- **Out of scope:** Writing status back to GitHub (sync-back is Phase 4).
- Only `ready` tasks are dispatched. `blocked` and `needs-info` are skipped.

## Files

| Path                          | Role                              |
|-------------------------------|-----------------------------------|
| `.claude-plugin/plugin.json`  | Plugin manifest                   |
| `bin/board-init`              | Bash: create/normalize canonical labels |
| `bin/board-pull`              | Bash: fetch issues via `gh`       |
| `bin/board-render`            | Python: generate board.json + TODO.md |
| `skills/*/SKILL.md`           | Skill definitions                 |
| `hooks/hooks.json`            | SessionStart board summary        |
| `docs/state-model.md`         | State mapping across representations |
| `docs/file-roles.md`          | Roles of generated files          |
| `tests/`                      | Self-contained render tests       |
