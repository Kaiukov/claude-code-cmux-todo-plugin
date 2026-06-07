# cmux-todo-board

Claude Code plugin that bridges GitHub Issues into a local task board,
mirrors ready tasks into Claude's built-in task list, and dispatches work
through cmux panes.

**Status:** MVP (one-directional: GitHub Issues → local board → task list).
Sync-back to GitHub is future work.

## Installation

### Via `/plugin` (recommended)

Run these inside Claude Code, from your project folder:

```
/plugin marketplace add Kaiukov/claude-code-cmux-todo-plugin
/plugin install cmux-todo-board@kaiukov-tools
```

The skills then appear as `/board-init`, `/board-pull`, etc. in that project.
Update later with `/plugin marketplace update kaiukov-tools`.

### Via local dir (development)

```bash
git clone https://github.com/Kaiukov/claude-code-cmux-todo-plugin
claude --plugin-dir ./claude-code-cmux-todo-plugin   # or /reload-plugins if running
```

## Quick start

Run from your project folder, once the plugin is installed:

```
/board-init --repo owner/repo    # 1. run ONCE per repo — create canonical labels
/board-pull --repo owner/repo    # 2. fetch issues → .tasks/board.json + TODO.md
/board-plan                      # 3. mirror `ready` issues into Claude's task list
/board-run-ready                 # 4. dispatch ready tasks into cmux panes
```

Label your issues with `ready` (or the other canonical statuses) so `board-pull`
picks them up. Review `TODO.md` between steps 2 and 3 to see everything grouped
by status.

## Skills

| Skill               | Description                                                |
|---------------------|------------------------------------------------------------|
| `/board-onboard`    | Run FIRST in a clean session — switch into orchestrator mode and load all board + cmux operating instructions. |
| `/board-init`       | Initialize a repo with canonical board status labels. Run once per repo before board-pull. |
| `/board-create-issue` | Turn a raw task description into a structured GitHub issue and create it. |
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

GitHub labels are the source of truth for status; `board.json` is a local cache
and `TODO.md` is a read-only render. See [Quick start](#quick-start) for the
command sequence.

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
