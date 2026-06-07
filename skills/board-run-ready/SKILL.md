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

Prefer the `cmux-agent-workflows` skill's scripts (`wt-new.sh`,
`agent-send.sh`, `pr-finish.sh`) if installed. Otherwise, raw cmux:

```
cmux new-split right
cmux rename-tab "<label>"
cmux send -- "<work prompt>"
```

## Verification (hard gate)

Never trust an agent's self-report. Run the project's tests **and**
`claude plugin validate .`. Both must pass before marking `completed`.

## MVP note

Status is NOT written back to GitHub labels. That is #5 sync-back.

## Fallback (no cmux)

List ready tasks via `bin/board-status` / `bin/board-next` for manual dispatch.
