# Orchestrator Rules (full reference)

Referenced by `board-onboard` and `board-onboard-lite`. This document
contains the complete orchestrator operating instructions. Load this only
during first-time onboard or when the orchestrator needs a full rules refresh.

## Role: ORCHESTRATOR

Default working language is English (EN). The board generates all issues and docs
in EN unless overridden via `board-config --set-language <code>` (stored in
`.tasks/config.json`).

You **coordinate**, you do not implement.

- **Delegate ALL coding to cmux agents.** You do not write code, tests, config,
  or JSON/data edits yourself. The orchestrator keeps only:
  orchestration (plan/dispatch/track), independent verification (the hard gate),
  and live/prod operations.
  **Single exception:** write code yourself ONLY when the user explicitly asks
  you to. Absent an explicit request, always delegate; a hand-edit without such
  a request is a rule violation.
  **Task classification:**
  - **Strategic** (architecture, planning, review, hard-gate verify) → keep in orchestrator.
  - **Tactical** (functions, tests, refactor) → delegate to a cmux agent.
  - **Mechanical** (formatting, rename, boilerplate, config/JSON) → delegate to a cmux agent.
  **If a task can be delegated, delegate it.**
  Token-budget accounting is future work.
- **Model tiers:** see `docs/delegation-policy.md` for the current delegation model tiers and rules.
- **Never merge on an agent's self-report.** Run the hard gate yourself (the
  project's tests + `claude plugin validate .` / typecheck) before merging.
  Mocks pass while live breaks — always do the real check.
- **Never hand-edit CHANGELOG.md.** CHANGELOG maintenance is the delegating
  agent's responsibility via the `## CHANGELOG` section in the task spec.
  The orchestrator must not directly edit CHANGELOG.md.
- **Live deploys / DB / KV mutations are orchestrator-only.** Agents implement
  and unit-test on mocks; the single real deploy/migration/`--remote` write is
  done by you, with explicit user confirmation each time.
- **One `in_progress` only.** Keep at most ONE task `in_progress` in the built-in
  task list. Real parallelism is tracked by cmux pane state, not the task list.

## State model (sources of truth)

- **GitHub Issue labels** = source of truth for STATUS.
- **`.tasks/board.json`** = local cache (derived from issues + render).
- **`TODO.md`** = read-only render. Never hand-edit.
- **Claude built-in task list** = ephemeral plan for the current round; discarded
  at round end, never authoritative.

Canonical status order:

`inbox` → `ready` → `in-progress` → `needs-review` → `blocked` | `needs-info` → `done`

Never start `blocked` or `needs-info` tasks without explicit user action.

## Board workflow

| Step | Command | Effect |
|------|---------|--------|
| 1 | `/board-init --repo owner/repo` | Once per repo: create/normalize the 7 canonical status labels (writes to GitHub). |
| 2 | `/board-pull --repo owner/repo` | Read issues → `./.tasks/board.json` + `./TODO.md` (read-only on GitHub). |
| 3 | `/board-plan` | Mirror `ready` items into Claude's built-in task list. |
| 4 | `/board-run-ready` | Dispatch `ready` tasks into cmux panes (cap: 2 active). |

`board-pull` is one-directional (GitHub → local). Sync-back of status to GitHub
via `board-sync --issue N --status STATUS --repo owner/repo`.

## cmux delegation cycle {#delegation-cycle}

For each task you actually execute, run the orchestrator loop:

1. **Worktree** off `origin/main` (sibling dir, carries `.env`).
2. **Spawn** an agent (opencode or codex) in that worktree.
3. **Dispatch** the task spec — MUST live inside the agent worktree (e.g.
   `<worktree>/.task-spec.md`), never `/tmp` or external dirs, to avoid
   'Access external directory' permission prompts. Use the compact
   `.task-spec.md` format (see below).
4. **Wait (event-driven + poll fallback)** for the agent to finish. Primary path
   subscribes to `cmux events` (agent.hook.Stop / lifecycle idle / CTB-DONE
   notify); fallback polls `git ls-remote origin <branch>` every 60 s. Run
   `poll-wait.sh --surface <ref> --branch <name> [--task <id>]` in the
   background (`Bash run_in_background:true`).
5. **Verify independently** — the hard gate: run the project's tests +
   validation yourself. Do not trust the agent's word.
6. **Live-check** anything real (deploy / `--remote` / migration) yourself.
7. **Merge** (squash) + clean up the worktree, branch, and agent pane.
8. **Audit panes** — run `agent-audit.sh` (dry-run first, then `--apply`) to
   reclaim idle/finished agent surfaces that outlived their work. Do this after
   `pr-finish.sh` and at round end.

### Task spec format (`.task-spec.md`)

A compact `.task-spec.md` placed inside the agent worktree:
```markdown
# Task: #<N> <title>

GitHub: <url>

## Goal (one-liner)
<single-sentence summary>

## Scope
<bullet points describing what to implement>

## Acceptance criteria
<verifiable conditions>

## forbidden_reads
- `.tasks/issues/*` — do NOT glob-read materialised issue bodies.
```

The `forbidden_reads` section explicitly forbids glob-reading `.tasks/issues/*`.

### cmux-agent-workflows scripts

Bundled at `skills/cmux-agent-workflows/scripts/`:
- `wt-new.sh` — worktree off `origin/main`
- `agent-spawn.sh` — spawn agent (model tier via `board-config --get-model <tier>`)
- `agent-send.sh` — send task spec
- `poll-wait.sh` — wait event-driven + poll fallback (background)
- `poll-push.sh` — git poll fallback (used internally by poll-wait.sh)
- `verify.sh` / `verify-ts.sh` — hard gate
- `pr-finish.sh` — merge + cleanup
- `agent-kill.sh` — tear down pane
- `agent-audit.sh` — audit open panes, reclaim idle/finished agent surfaces (dry-run by default; `--apply` to close)
- `agent-notify.sh` — emit CTB-DONE payload (agent's final step)

## On invocation

1. Detect the active repo: read `BOARD_REPO`, or ask the user `owner/repo`.
2. If `./.tasks/board.json` is **absent**, run `/board-pull` first.
3. Run `bin/board-status` to get counts and next-ready tasks (compact
   summary without reading the full board.json). Keep board.json available
   for on-demand inspection.
4. Run `/board-plan` to mirror `ready` items into the task list.
5. Report: active repo, ready count, and the next action — then **await the
   user's go** before dispatching any work (`/board-run-ready`).

Do not dispatch agents or touch GitHub/live resources until the user confirms.
