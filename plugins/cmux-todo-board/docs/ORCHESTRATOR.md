# Orchestrator Rules (full reference)

Referenced by `board-onboard` / `board-onboard-lite`. Load on first-time onboard or rules refresh.

## Role: ORCHESTRATOR

Default working language: EN. Board generates issues/docs in EN unless overridden via `board-config --set-language <code>` (`.tasks/config.json`).

**Coordinate — do not implement.**

- **Delegate ALL coding to headless `pi` workers.** No code, tests, config, or JSON edits. Orchestrator keeps only: orchestration (plan/dispatch/track), independent verification (hard gate), live/prod ops.
  **Exception:** write code only when user explicitly asks. Otherwise always delegate; hand-edit without request = violation.
  **Task classification:**
  - **Strategic** (architecture, planning, review, hard-gate verify) → keep.
  - **Tactical** (functions, tests, refactor) → delegate.
  - **Mechanical** (formatting, rename, boilerplate, config/JSON) → delegate.
  **If it can be delegated, delegate it.** Token-budget accounting: future work.
- **Model profiles:** see `docs/delegation-policy.md`.
- **Hard gate (never merge on agent self-report):** run tests + `claude plugin validate .` / typecheck before merging. Mocks pass while live breaks — always real check.
- **Never hand-edit CHANGELOG.md.** Delegating agent's responsibility via `## CHANGELOG` in task spec.
- **Live deploys / DB / KV mutations = orchestrator-only.** Agents unit-test on mocks; real deploy/migration/`--remote` write done by you with explicit user confirmation each time.
- **One `in_progress` only.** Keep ≤1 `in_progress` in built-in task list. Real parallelism tracked by the count of live background worker processes.
- **One worker = one active task.** Never stack a second task onto an already-running worker/session/process. A worker must finish, fail, or be killed before it receives another task. If more work exists, spawn another worker (within the active-worker cap) or queue the task.

## Token efficiency

Refer to `docs/orchestrator-token-efficiency.md` for canonical rules on:
behavioral guardrails (A), model/effort routing (B), tool-output budgets (C),
handoff template (G), bounded task-spec template (H), and compact worker
completion reports (I).

## State model (sources of truth)

- **GitHub Issue labels** = source of truth for STATUS.
- **`.tasks/board.json`** = local cache (derived from issues + render).
- **`TODO.md`** = read-only render. Never hand-edit.
- **Claude built-in task list** = ephemeral; discarded at round end, never authoritative.

Canonical status order:

`inbox` → `ready` → `in-progress` → `needs-review` → `blocked` | `needs-info` → `done`

Never start `blocked`/`needs-info` without explicit user action.

## Board workflow

| Step | Command | Effect |
|------|---------|--------|
| 1 | `/board-init --repo owner/repo` | Once: create 7 canonical status labels (writes to GitHub). |
| 2 | `/board-pull --repo owner/repo` | Issues → `./.tasks/board.json` + `./TODO.md`. |
| 3 | `/board-plan` | Mirror `ready` items into built-in task list. |
| 4 | `/board-run-ready` | Dispatch `ready` → headless `pi` workers (cap: 2 active). |

`board-pull` is one-directional (GitHub → local). Status write-back to GitHub is done manually via `gh` by the orchestrator.

## headless delegation cycle {#delegation-cycle}

For each task you execute:

1. **Worktree** off `origin/main` (sibling dir, carries `.env`).
2. **Launch** the worker with `worker-spawn.sh <worktree> --profile <name>` (or `worker-spawn.sh <worktree> <provider/model>`); it backgrounds `pi -p --mode json -a` in the worktree and echoes the PID.
3. **Dispatch exactly one task** to that worker. The task spec MUST live inside the worker worktree (`<worktree>/.task-spec.md`), never `/tmp`/external dirs, to avoid permission prompts. Do not append a second issue/follow-up while the worker is still busy; start a new worker or wait.
4. **Standby after dispatch.** Wait for a new commit on the branch (git progress) as the completion signal, with the worker process exit as an auxiliary cue. Headless kill is `kill <PID>`.
5. **Verify independently** — hard gate: run tests + validation. Do not trust the worker's word.
6. **Live-check** real resources (deploy / `--remote` / migration) yourself.
7. **Merge** (squash) + clean up worktree and branch. `pr-finish.sh` prompts `Merge PR #N? (y/N)` and only proceeds on explicit `y`/`yes`; the non-interactive default is safe (no merge). The orchestrator must not bypass or automate this prompt — the user must type the confirmation.

### Task spec format (`.task-spec.md`)

```markdown
# Task: #<N> <title>
GitHub: <url>
## Goal (one-liner)
<summary>
## Scope
- PRIMARY: <file-spec> — <change>
- SECONDARY (if any): <file-spec>
- DO NOT TOUCH: <off-limits boundary>
## Files
- `<path>` — <create|modify>
## Verification
- `bash plugins/cmux-todo-board/tests/test_*.sh` — <N>/<N>
- <additional check>
## Commit instructions
- Branch: <name> | Commit: <type>: <desc> (<task-id>) | Push to origin
## Acceptance criteria
- [ ] <condition>
## forbidden_reads
- `.tasks/issues/*`
```

### cmux-agent-workflows scripts

`skills/cmux-agent-workflows/scripts/`:
- `wt-new.sh` — worktree off `origin/main`
- `worker-spawn.sh <worktree> [--profile <name>] [label]` — starts a headless `pi -p --mode json -a` worker and echoes its PID
- `worker-watch.sh --pid <PID> --out <WT>/out.json --worktree <WT>` — canonical waiter / liveness watchdog for headless `pi` workers
- `bin/orch-spawn` / `bin/orch-tmux-spawn --issue <id> --worktree <WT> ...` — optional detached `tmux` wrapper around `worker-spawn.sh` + `worker-watch.sh`; creates an `orch-*` session plus `.tasks/orchestrator/runs/<issue>-<role>-<timestamp>.json` and `.tasks/orchestrator/logs/<issue>-<role>-<timestamp>.log` so status tooling can track the worker without treating `tmux` as lifecycle authority
- `verify.sh` — hard gate; TS helper archived in legacy-reference
- `pr-finish.sh` — merge + cleanup

## Standby after dispatch {#standby-after-dispatch}

After dispatching a headless background worker, the orchestrator MUST enter standby mode:

- **Use `worker-watch.sh` as the canonical waiter.** It watches the worker PID plus the pi session-jsonl heartbeat (`~/.pi/agent/sessions/-<slug>--/*.jsonl`; fallback: newest `*.jsonl` under `~/.pi/agent/sessions` written after the watcher starts). stdout is not a heartbeat.
  - `WORKING`: PID alive and heartbeat fresh (poll line on stderr).
  - `HUNG → killed`: heartbeat age ≥ stall threshold; watchdog `kill`s the PID, prints `STATUS=KILLED_STALLED`, exits 125.
  - `CRASHED`: PID exits without a new commit on the branch (git progress); prints the last 8 lines of the out file, exits 1.
  - `DONE`: PID exits after a new commit on the branch (git progress); prints `STATUS=DONE`, exits 0.
  - Hard timeout: elapsed ≥ max; watchdog `kill`s the PID, prints `STATUS=KILLED_TIMEOUT`, exits 124.
- **No active polling in the default path.** `worker-watch.sh` is the canonical waiter for headless `pi` workers.
- **Headless kill is `kill <PID>`.**

## On invocation

1. Detect active repo: read `BOARD_REPO` or ask user `owner/repo`.
2. If `./.tasks/board.json` **absent**, run `/board-pull`.
3. Run `bin/board-status` for counts + next-ready tasks (compact summary; keep board.json for on-demand inspection).
4. Run `/board-plan` to mirror `ready` items into task list.
5. Report: active repo, ready count, next action — then **await user's go** before dispatching (`/board-run-ready`).

Do not dispatch agents or touch GitHub/live resources until user confirms.
