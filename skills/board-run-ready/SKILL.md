---
name: board-run-ready
description: Dispatch ready tasks into cmux panes for parallel execution.
---

# board-run-ready

Dispatches each `ready` task from `.tasks/board.json` into a cmux pane for
parallel agent execution.

## Prerequisites

The native `cmux` CLI must be on PATH. Verify with:

```bash
cmux current-workspace
```

If `cmux` is not available, the skill falls back to listing ready tasks for
manual dispatch.

## Concurrency

- **Default cap: 2 active cmux panes.** Do not exceed without explicit user request.
- Up to 2 cmux panes may be active simultaneously, but the built-in task list
  tracks only the current orchestrator focus task as `in_progress`. All other
  dispatched tasks remain `pending` in the task list while their cmux panes run.
- The orchestrator keeps at most ONE task `in_progress` in its built-in task
  list; cmux pane state is the real concurrency tracker.

## Dispatch Procedure

For each `ready` task (up to the concurrency cap):

1. **Open a working pane:**
   ```bash
   cmux new-split right
   ```
   Or `down` depending on layout preference. Note the surface reference.

2. **Name the tab:**
   ```bash
   cmux rename-tab --surface <ref> "#<number> <short-title>"
   ```

3. **Send the work command:**
   ```bash
   cmux send --surface <ref> -- "Work on GitHub issue #<number>: <title>. URL: <url>"
   ```

4. **Update task state:** Mark the task as `in_progress` in Claude's built-in
   task list.

5. **Monitor:** Read pane output periodically. When work is verified, mark the
   task as `completed` in the built-in task list.

## Status Notes (MVP)

In this MVP, status is NOT written back to GitHub labels. That is future work
(Phase 4 sync-back). The `completed` state exists only in the current round's
built-in task list.

## Fallback (no cmux)

If `cmux` is not on PATH, print the list of ready tasks and instruct the user
to dispatch manually:

```
Ready tasks for manual dispatch:
  - #2 Implement user authentication (https://...)
  - #8 Add dashboard widget (https://...)

Open each in a cmux pane and send the issue URL as the prompt.
```
