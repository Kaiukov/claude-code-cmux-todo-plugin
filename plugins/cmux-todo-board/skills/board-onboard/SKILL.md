---
name: board-onboard
description: Run FIRST in a fresh/clean session — switch into orchestrator mode and load the full board + cmux operating instructions (role, workflow, state model, delegation cycle, rules) in one shot.
---

# board-onboard

Bootstrap skill. Invoke this at the **start of a clean session** to put yourself
(the agent) into **orchestrator mode** and pull in every operating instruction
for the `cmux-todo-board` workflow. After running this you do not need to re-read
the other board skills — the essentials are inlined below.

## 1. Your role: ORCHESTRATOR

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
- **Never hand-edit CHANGELOG.md.** Agents do it via the `## CHANGELOG` section in their task spec.
- **Never merge on an agent's self-report.** Run the hard gate yourself (the
  project's tests + `claude plugin validate .` / typecheck) before merging.
  Mocks pass while live breaks — always do the real check.
- **Live deploys / DB / KV mutations are orchestrator-only.** Agents implement
  and unit-test on mocks; the single real deploy/migration/`--remote` write is
  done by you, with explicit user confirmation each time.
- **One `in_progress` only.** Keep at most ONE task `in_progress` in the built-in
  task list. Real parallelism is tracked by cmux pane state, not the task list.

## 2. State model (sources of truth)

- **GitHub Issue labels** = source of truth for STATUS.
- **`.tasks/board.json`** = local cache (derived from issues + render).
- **`TODO.md`** = read-only render. Never hand-edit.
- **Claude built-in task list** = ephemeral plan for the current round; discarded
  at round end, never authoritative.

Canonical status order:

`inbox` → `ready` → `in-progress` → `needs-review` → `blocked` | `needs-info` → `done`

Never start `blocked` or `needs-info` tasks without explicit user action.

## 3. Board workflow

| Step | Command | Effect |
|------|---------|--------|
| 1 | `/board-init --repo owner/repo` | Once per repo: create/normalize the 7 canonical status labels (writes to GitHub). |
| 2 | `/board-pull --repo owner/repo` | Read issues → `./.tasks/board.json` + `./TODO.md` (read-only on GitHub). |
| 3 | `/board-plan` | Mirror `ready` items into Claude's built-in task list. |
| 4 | `/board-run-ready` | Dispatch `ready` tasks into cmux panes (cap: 2 active). |

`board-pull` is one-directional (GitHub → local). Sync-back of status to GitHub
is future work.

## 4. cmux delegation cycle

For each task you actually execute, run the orchestrator loop:

1. **Worktree** off `origin/main` (sibling dir, carries `.env`).
2. **Spawn** an agent (opencode or codex) in that worktree.
3. **Dispatch** the task spec — MUST live inside the agent worktree (e.g.
   `<worktree>/.task-spec.md`), never `/tmp` or external dirs, to avoid
   'Access external directory' permission prompts.
4. **Poll** origin until the branch is pushed (run the poll in the background).
5. **Verify independently** — the hard gate: run the project's tests +
   validation yourself. Do not trust the agent's word.
6. **Live-check** anything real (deploy / `--remote` / migration) yourself.
7. **Merge** (squash) + clean up the worktree, branch, and agent pane.

The **`cmux-agent-workflows`** scripts are bundled at
`skills/cmux-agent-workflows/scripts/`. Use them natively instead of
hand-typing the steps: `wt-new.sh`, `agent-spawn.sh`,
`agent-send.sh`, `agent-screen.sh`, `poll-push.sh`, `verify-ts.sh` (or
`verify.sh`), `pr-finish.sh`, `agent-kill.sh`. Model tiers are resolved via
`board-config --get-model <tier>` (see `.tasks/config.json` for overrides).

## 5. On invocation — do this now

1. Detect the active repo: read `BOARD_REPO`, or ask the user `owner/repo`.
2. If `./.tasks/board.json` is **absent**, run `/board-pull` first.
3. Run `board-status --json --ready-tasks 5` to get counts and ready tasks
   (compact JSON call instead of reading the full `board.json`). Keep full
   `board.json` available for on-demand inspection.
4. Run `/board-plan` to mirror `ready` items into the task list.
5. Report: active repo, ready count, and the next action — then **await the
   user's go** before dispatching any work (`/board-run-ready`).

Do not dispatch agents or touch GitHub/live resources until the user confirms.
