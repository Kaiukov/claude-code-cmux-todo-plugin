# Orchestrator Rules (full reference)

Referenced by `board-onboard` / `board-onboard-lite`. Load on first-time onboard or rules refresh.

## Role: ORCHESTRATOR

Default working language: EN. Board generates issues/docs in EN unless overridden via `board-config --set-language <code>` (`.tasks/config.json`).

**Coordinate — do not implement.**

- **Delegate ALL coding to cmux agents.** No code, tests, config, or JSON edits. Orchestrator keeps only: orchestration (plan/dispatch/track), independent verification (hard gate), live/prod ops.
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
- **One `in_progress` only.** Keep ≤1 `in_progress` in built-in task list. Real parallelism tracked by cmux pane state.

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
| 4 | `/board-run-ready` | Dispatch `ready` → cmux panes (cap: 2 active). |

`board-pull` is one-directional (GitHub → local). Sync-back via `board-sync --issue N --status STATUS --repo owner/repo`.

## cmux delegation cycle {#delegation-cycle}

For each task you execute:

1. **Worktree** off `origin/main` (sibling dir, carries `.env`).
2. **Spawn** agent (opencode/codex) in worktree.
3. **Dispatch** task spec — MUST live inside agent worktree (`<worktree>/.task-spec.md`), never `/tmp`/external dirs, to avoid permission prompts. Use compact format (below).
4. **Standby after dispatch.** See [standby rule](#standby-after-dispatch). Wait for completion signal or user nudge — do not actively poll the agent pane.
5. **Verify independently** — hard gate: run tests + validation. Do not trust agent's word.
6. **Live-check** real resources (deploy / `--remote` / migration) yourself.
7. **Merge** (squash) + clean up worktree, branch, agent pane. `pr-finish.sh` prompts `Merge PR #N? (y/N)` and only proceeds on explicit `y`/`yes`; the non-interactive default is safe (no merge). The orchestrator must not bypass or automate this prompt — the user must type the confirmation.
8. **Audit panes** — run `agent-audit.sh` (dry-run first, then `--apply`) to reclaim idle/finished surfaces. After `pr-finish.sh` and at round end.

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
- `agent-spawn.sh` — spawn agent (model via `--profile <name>` or raw model id)
- `agent-send.sh` — send task spec
- `poll-wait.sh` — event-driven + poll fallback (background)
- `poll-push.sh` — git poll fallback (internal to poll-wait.sh)
- `verify.sh` / `verify-ts.sh` — hard gate
- `pr-finish.sh` — merge + cleanup
- `agent-kill.sh` — tear down pane
- `agent-audit.sh` — audit panes, reclaim idle/finished surfaces (dry-run default; `--apply` to close)
- `agent-notify.sh` — emit CTB-DONE payload

## Standby after dispatch {#standby-after-dispatch}

After dispatching an agent into a cmux pane, the orchestrator MUST enter standby mode:

- **Do not screen-scrape the pane.** `agent-screen.sh`, `agent-send.sh` with read flags, and similar progress checks are prohibited while the agent is working.
- **Wait on the event stream in the background.** `poll-wait.sh` is the primary waiter; it listens to `cmux events --category agent --category notification` and resolves on either an agent idle/Stop event or a `CTB-DONE` notification. `poll-push.sh` is only the fallback if the event path is missed.
- **Read once after a signal.** After `poll-wait.sh` or an explicit user nudge says the agent is done, a single `agent-screen.sh <surface> <N>` call (≤40 lines) is allowed to read the final report.
- **Do not type into a working agent pane.** `agent-send.sh` MUST NOT be called against an active agent surface until the agent has completed or the user explicitly instructs intervention.

## On invocation

1. Detect active repo: read `BOARD_REPO` or ask user `owner/repo`.
2. If `./.tasks/board.json` **absent**, run `/board-pull`.
3. Run `bin/board-status` for counts + next-ready tasks (compact summary; keep board.json for on-demand inspection).
4. Run `/board-plan` to mirror `ready` items into task list.
5. Report: active repo, ready count, next action — then **await user's go** before dispatching (`/board-run-ready`).

Do not dispatch agents or touch GitHub/live resources until user confirms.
