---
name: board-onboard
description: Advanced orchestrator bootstrap — on-demand / advanced only. Loads full role rules, workflow, and operating instructions. Needed for backend internals, hook installation, codex trust behavior, live-deploy traps, detailed troubleshooting, and script implementation details. For routine sessions, use board-onboard-lite.
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

## 4. Delegation cycle

The canonical cycle is **worktree → spawn → dispatch → wait → verify → merge → cleanup**.
See `board-onboard-lite` for the compact reference or `cmux-agent-workflows-lite` for the
script-based workflow. Full script documentation lives in `cmux-agent-workflows` (on-demand).

> **On-demand detail — task spec placement:** The `.task-spec.md` MUST live inside the agent
> worktree (`<worktree>/.task-spec.md`), never `/tmp` or external dirs, to avoid
> 'Access external directory' permission prompts. Model profiles are resolved via
> `board-config --get-profile <name)`.

## 5. On invocation

Follow the standard invocation flow in `board-onboard-lite`. The routine steps are:

1. Detect the active repo (read `BOARD_REPO` or ask the user `owner/repo`).
2. If `./.tasks/board.json` is absent, run `board-pull`.
3. Run `board-status --json --ready-tasks 5`.
4. Run `board-plan` to mirror ready items.
5. Report and **await the user's go** before dispatching.

> **On-demand detail — inspection:** Keep the full `board.json` available for manual inspection
> when debugging task states or label assignments. The compact `board-status` call covers
> routine needs.
