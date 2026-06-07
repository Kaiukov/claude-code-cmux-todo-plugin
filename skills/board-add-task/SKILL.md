---
name: board-add-task
description: Add a local task without a GitHub issue; agent asks only which status/step.
---

# board-add-task

Add a **local task** to the board — no GitHub issue is created. Local tasks live
in `.tasks/local.json`, survive `board-pull`, and are merged into the board by
`board-render`.

```
/board-add-task <raw task text>
```

## Notes

Local tasks are local-only, never pushed to GitHub (#5 is the separate sync-back
feature). They live in `.tasks/local.json`.

## Procedure

1. Take the raw task text (everything after the command).

2. Ask the user ONLY which status/step to place it at (the canonical statuses),
   defaulting to `ready` for immediately-actionable tasks. Do not ask anything
   else.

   Valid statuses: `inbox`, `ready`, `in-progress`, `needs-review`, `blocked`,
   `needs-info`, `done`.

3. Run `bin/board-add --status <chosen> "<title>"`.

4. Report the local id + status, and suggest `/board-plan` (then
   `/board-run-ready` if `ready`).
