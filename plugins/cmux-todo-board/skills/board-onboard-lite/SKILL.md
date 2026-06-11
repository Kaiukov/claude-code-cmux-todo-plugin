---
name: board-onboard-lite
description: Lightweight orchestrator bootstrap — emits a compact summary (role, key commands, doc links) instead of the full inlined rules. Use when token budget is tight. For first-time onboard, use board-onboard.
---

# board-onboard-lite

Compact orchestrator bootstrap. Loads the essentials in minimal tokens.
For the full first-time onboard, use `board-onboard` instead.

## Your role: ORCHESTRATOR

Coordinate, do not implement. Delegate coding to cmux agents.
Never hand-edit CHANGELOG.md (agents do it via their task spec).
Only exception: the user explicitly asks you to write code.

Key docs: `docs/ORCHESTRATOR.md` (full rules), `docs/delegation-policy.md` (model tiers).

## State model

- GitHub Issue labels = source of truth for STATUS.
- `.tasks/board.json` = local cache.
- `TODO.md` = read-only render.
- Claude built-in task list = ephemeral, discarded at round end.

Canonical status order:
`inbox` → `ready` → `in-progress` → `needs-review` → `blocked` | `needs-info` → `done`

## Key commands

| Command | Effect |
|---------|--------|
| `board-pull --repo owner/repo` | Fetch issues → `.tasks/board.json` |
| `board-sync --issue N --status S` | Write status back to GitHub labels |
| `board-release --bump patch` | SemVer release helper |
| `board-plan` | Mirror ready tasks into task list |
| `board-run-ready` | Dispatch ready tasks to cmux panes |

## Delegation cycle (compact)

1. `wt-new.sh` → worktree | 2. `agent-spawn.sh` → spawn agent
3. `agent-send.sh` → dispatch `.task-spec.md` | 4. `poll-push.sh` → poll (bg)
5. `verify.sh` → hard gate | 6. `pr-finish.sh` → merge | 7. `agent-kill.sh` → cleanup

Scripts: `skills/cmux-agent-workflows/scripts/`.

## On invocation

1. Detect repo (BOARD_REPO or ask).
2. If absent, run `board-pull`.
3. Run `board-status --json --ready-tasks 5` to get counts and ready tasks
   (compact JSON call instead of reading full `board.json`).
4. Run `board-plan` to mirror ready.
5. Report and await user confirmation before dispatching.
