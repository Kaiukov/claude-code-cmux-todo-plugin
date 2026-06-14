# cmux-todo-board

Claude Code plugin that bridges GitHub Issues into a local task board,
mirrors ready tasks into Claude's built-in task list, and dispatches work
to headless `pi` workers orchestrated under tmux via the `orch-*` pipeline.

**Status:** MVP (one-directional: GitHub Issues → local board → task list).
Sync-back to GitHub is future work. Installation is designed to source the marketplace
from GitHub so `/plugin marketplace update` pulls the latest `main`.

## Installation

### Via `/plugin` (recommended)

Run these inside Claude Code, from your project folder:

```
/plugin marketplace add Kaiukov/claude-code-cmux-todo-plugin
/plugin install cmux-todo-board@kaiukov-tools
```

The skills then appear as `/board-init`, `/board-pull`, etc. in that project.
Update later with `/plugin marketplace update kaiukov-tools`.

### Updating

Plugins never auto-update silently — update is always a manual command.
When the marketplace is registered from GitHub, run these inside Claude Code:

```
/plugin marketplace update kaiukov-tools
/reload-plugins
```

This re-reads the latest `main` from GitHub and reloads skills and hooks.

### Via local dir (development / fallback)

```bash
git clone https://github.com/Kaiukov/claude-code-cmux-todo-plugin
claude --plugin-dir ./claude-code-cmux-todo-plugin   # or /reload-plugins if running
```

### Troubleshooting

**`ERR_STREAM_PREMATURE_CLOSE` during `marketplace add`**

This is a known upstream race in Claude Code's plugin manager when it streams
git child-process stdio. The repo itself is public and reachable over both SSH
and HTTPS — the same `git clone` command succeeds when run by hand. The plugin
manager always passes `--recurse-submodules --shallow-submodules`; this repo
has no `.gitmodules`, so submodule flags are a guaranteed no-op and are not the
cause.

**Workaround A — retry (transient):** The stdio race sometimes clears on retry.
Run `/plugin marketplace add Kaiukov/claude-code-cmux-todo-plugin` again.

**Workaround B — local-directory fallback (always works):**

```bash
git clone https://github.com/Kaiukov/claude-code-cmux-todo-plugin
```

Then inside Claude Code register the checkout as a Directory source:

```
/plugin marketplace add ./claude-code-cmux-todo-plugin   # Source: Directory
```

Update later with:

```bash
git -C ./claude-code-cmux-todo-plugin pull
```

Then inside Claude Code:

```
/plugin marketplace update kaiukov-tools
/reload-plugins
```

The GitHub-sourced path is the intended primary flow; the local-directory path
is the developer fallback when the upstream race surfaces.

## Quick start

Run from your project folder, once the plugin is installed:

```
/board-init --repo owner/repo    # 1. run ONCE per repo — create canonical labels
/board-pull --repo owner/repo    # 2. fetch issues → .tasks/board.json + TODO.md
/board-plan                      # 3. mirror `ready` issues into Claude's task list
/board-run-ready                 # 4. dispatch ready tasks to headless `pi` workers
```

Label your issues with `ready` (or the other canonical statuses) so `board-pull`
picks them up. Review `TODO.md` between steps 2 and 3 to see everything grouped
by status.

## Skills

| Skill | Description |
|---|---|
| `/board-onboard` | Run FIRST in a clean session — switch into orchestrator mode and load all board + orchestrator operating instructions. |
| `/board-onboard-lite` | Compact orchestrator bootstrap for token-constrained sessions. Full rules at `plugins/cmux-todo-board/docs/ORCHESTRATOR.md`. |
| `/cmux-agent-workflows` | Advanced headless-pi orchestration helpers and script reference. |
| `/board-init` | Initialize a repo with canonical board status labels. Run once per repo before board-pull. |
| `/board-create-issue` | Turn a raw task description into a structured GitHub issue and create it. |
| `/board-add-task` | Add a local task without a GitHub issue. Local tasks live in `.tasks/local.json` and never touch GitHub. Local task status can be updated via `board-add --set <id> --status <status>`. |
| `/board-pull` | Fetch GitHub issues and render the local board. Supports `--strategy all-open` (default, one API call + local filter) and `--strategy labels` (per-label queries unioned). Use `--with-body` to include body text. |
| `/board-release` | Bump SemVer versions, create git tags, and publish GitHub Releases with opt-in network safety gates. |
| `/board-plan` | Mirror ready tasks into Claude's built-in task list (cap: 5). |
| `/board-run-ready` | Dispatch ready tasks to headless `pi` workers for parallel execution. Generates compact `.task-spec.md` with `forbidden_reads` guard. |
| `/board-config` | Manage board runtime configuration and Pi profile resolution in `.tasks/config.json`. |
| `/board` | Show the board flow and operating rules. |
| `/orchestrator-onboard` | Auto-switch to orchestrator mode and run first-run preflight. |
| `/orchestrator-dispatch` | Dispatch one ready issue to the correct worker role. |
| `/orchestrator-standby` | Watch a run passively for process and git progress. |
| `/orchestrator-status` | Show one compact snapshot from live orchestrator state. |
| `/orchestrator-verify` | Run the hard gate, review the diff, and report pass or fail. |
| `/orchestrator-finish` | Close out the local run and remind the human merge gate rules. |

## Workflow

```
GitHub Issues  --board-pull-->  .tasks/board.json  --board-plan-->  Claude task list
                                                              |
                                                              v
                                         board-run-ready --> headless pi workers via orch-*
```

GitHub labels are the source of truth for status; `board.json` is a local cache
and `TODO.md` is a read-only render. The board is one-directional (GitHub → local);
status sync-back to GitHub is future work. See [Quick start](#quick-start) for the
command sequence.

## Verification

```bash
# Run the board-render tests
bash plugins/cmux-todo-board/tests/test_board_render.sh

# Run the union/dedup logic tests
bash plugins/cmux-todo-board/tests/test_board_pull_union.sh

# Run the orchestrator config tests
bash plugins/cmux-todo-board/tests/test_orch_config.sh

# Validate plugin structure (if claude CLI available)
claude plugin validate .
```

## Scope

- **MVP (Phase 1):** Pull issues → render board → plan → dispatch.
- Only `ready` tasks are dispatched. `blocked` and `needs-info` are skipped.

## Files

| Path | Role |
|---|---|
| `.claude-plugin/plugin.json` | Plugin manifest |
| `plugins/cmux-todo-board/bin/board-init` | Bash: create/normalize canonical labels |
| `plugins/cmux-todo-board/bin/board-pull` | Bash: fetch issues via `gh` (--with-body for full body) |
| `plugins/cmux-todo-board/bin/board-render` | Python: generate board.json + TODO.md |
| `plugins/cmux-todo-board/bin/board-render-body` | Bash: on-demand full-body retrieval for a single issue |
| `plugins/cmux-todo-board/bin/board-status` | Bash: compact board state for the orchestrator (counts + next ready) |
| `plugins/cmux-todo-board/bin/board-next` | Bash: return next actionable task for a given status |
| `plugins/cmux-todo-board/bin/orch-dispatch`, `plugins/cmux-todo-board/bin/orch-finish`, `plugins/cmux-todo-board/bin/orch-spawn`, `plugins/cmux-todo-board/bin/orch-status`, `plugins/cmux-todo-board/bin/orch-statusline`, `plugins/cmux-todo-board/bin/orch-tmux-spawn`, `plugins/cmux-todo-board/bin/orch-verify`, `plugins/cmux-todo-board/bin/orch-watch` | Orchestrator scripts for headless `pi` dispatch, standby, and verification |
| `plugins/cmux-todo-board/skills/cmux-agent-workflows/SKILL.md` | Advanced headless-pi orchestration helpers |
| `plugins/cmux-todo-board/skills/` | Skill definitions |
| `hooks/hooks.json` | SessionStart board summary |
| `plugins/cmux-todo-board/docs/state-model.md` | State mapping across representations |
| `plugins/cmux-todo-board/docs/file-roles.md` | Roles of generated files |
| `plugins/cmux-todo-board/docs/ORCHESTRATOR.md` | Full orchestrator operating rules (referenced by board-onboard-lite) |
| `plugins/cmux-todo-board/tests/` | Self-contained render tests |
| `.tasks/board.json` | Generated: local board cache |
| `.tasks/issues.json` | Generated: fetched GitHub issues |
| `.tasks/issues/<n>.md` | Per-issue body cache for workers (not committed; `.tasks/` is gitignored) |
| `TODO.md` | Generated: read-only task board |
