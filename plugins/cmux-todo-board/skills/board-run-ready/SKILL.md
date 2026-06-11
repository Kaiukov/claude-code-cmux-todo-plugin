---
name: board-run-ready
description: Dispatch ready tasks into cmux panes for parallel execution.
---

# board-run-ready

Dispatches ready tasks from `.tasks/board.json` into cmux panes for parallel
agent execution.

## Prerequisites

- `.tasks/board.json` exists — run `/board-pull` first.
- `cmux` on PATH. Falls back to listing tasks if not available.

## Pick work

Use compact helpers, not a full board read:
- `bin/board-status` → status counts + next ready (one line).
- `bin/board-next --json` → next ready task object.

## Concurrency

- Cap: 2 active cmux panes.
- At most ONE task `in_progress` in the built-in task list.
- Cmux pane state is the real tracker; other dispatched tasks stay `pending`.

## Dispatch

### Step 0: Generate `.task-spec.md`

Before spawning an agent, generate a compact `.task-spec.md` inside the agent
worktree (`<worktree>/.task-spec.md`). Never place it in `/tmp` or external
directories. Use this format:

```markdown
# Task: #<N> <title>

GitHub: <url>

## Goal (one-liner)
<single-sentence summary of what needs to be done>

## Scope
<bullet points describing affected files, implementation boundaries>

## Acceptance criteria
<verifiable conditions — e.g. tests pass, plugin validate, no new lint>

## CHANGELOG
Add an entry under `CHANGELOG.md`'s `## [Unreleased]` using the correct
Keep-a-Changelog subsection (`### Added`, `### Changed`, `### Fixed`, etc.)
that matches the type of change. Reference this task id in the entry.

## forbidden_reads
- `.tasks/issues/*` — do NOT glob-read materialised issue bodies.
```

The `forbidden_reads` section is required. It must explicitly forbid
glob-reading `.tasks/issues/*` to prevent accidental token leakage from
materialised issue body files.

### Steps 1–8

See the [canonical delegation cycle in `docs/ORCHESTRATOR.md`](../docs/ORCHESTRATOR.md#cmux-delegation-cycle). The scripts at `skills/cmux-agent-workflows/scripts/` map one-to-one to the steps there. Only the procedural loop is shared — all board-run-ready–specific constraints (below) still apply.

## Verification (hard gate)

Never trust an agent's self-report. Run the project's tests **and**
`claude plugin validate .`. Both must pass before marking `completed`.

## Completion notification flow

- **PRIMARY:** `agent-notify.sh` — the work prompt MUST instruct the agent to
  call this as its final step (success or failure). Emits a `CTB-DONE` payload
  via `cmux notify` (if on PATH) or stdout. The payload carries: task id,
  surface ref, status (success|failure), and branch name if pushed.
- **FALLBACK:** `poll-push.sh` (branch polling). A missed event never strands
  a task; the fallback catches completions the signal missed.

## MVP note

Status is NOT written back to GitHub labels. That is #5 sync-back.

## Fallback (no cmux)

List ready tasks via `bin/board-status` / `bin/board-next` for manual dispatch.
