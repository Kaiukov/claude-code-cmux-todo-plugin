---
name: board-onboard-lite
description: Default orchestrator bootstrap — loads a compact role summary, key commands, and delegation cycle for routine sessions. For advanced scenarios (backend internals, hook installation, codex trust, live-deploy traps, detailed troubleshooting), use board-onboard.
---

# board-onboard-lite

Compact orchestrator bootstrap. Loads the essentials in minimal tokens.
For the full first-time onboard, use `board-onboard` instead.

## Your role: ORCHESTRATOR

Coordinate, do not implement. Delegate coding to headless `pi -p` workers.
Never hand-edit CHANGELOG.md (agents do it via their task spec).
Only exception: the user explicitly asks you to write code.

Key docs: `docs/ORCHESTRATOR.md` (full rules), `docs/delegation-policy.md` (model profiles).

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
| `board-run-ready` | Dispatch ready tasks to headless `pi` workers (cap: 2; parked 3×3 dashboard optional) |

## Delegation cycle (compact)

1. `wt-new.sh` → worktree
2. Launch the canonical headless `pi -p` worker in the worktree (see `docs/ORCHESTRATOR.md` for the full command)
3. Dispatch `.task-spec.md` inside the worktree
4. Standby — wait for process exit code + `CTB-DONE` + branch commit (no active polling)
5. `verify.sh` → hard gate
6. `pr-finish.sh` → merge
7. Optional dashboard only: `agent-audit.sh` / `agent-screen.sh` / `agent-notify.sh` / `poll-wait.sh` / `poll-push.sh` for watch/intervene on the parked 3×3 dashboard

## On invocation

1. Detect repo (BOARD_REPO or ask).
2. If absent, run `board-pull`.
3. Run `board-status --json --ready-tasks 5` to get counts and ready tasks
   (compact JSON call instead of reading full `board.json`).
4. Run `board-plan` to mirror ready.
5. Report and await user confirmation before dispatching.
