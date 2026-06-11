---
name: board-plan
description: Read board.json and mirror ready tasks into Claude's built-in task list.
---

# board-plan

Reads `.tasks/board.json`, selects ONLY tasks with status `ready`, and creates
entries in Claude's built-in task list for the current round.

## Rules

- **Only `ready` tasks are mirrored.** `inbox`, `blocked`, `needs-info`,
  `needs-review`, `in-progress`, and `done` tasks are skipped.
- **Cap: 5 ready tasks mirrored.** The default limit is 5. If there are more
  than 5 ready tasks, emit only the first 5, then a summary line:
  `… and N more ready tasks (see board.json)`.
- **The task list is ephemeral.** These entries exist only for the current
  round. They disappear when the session ends.
- **Use the Task tools provider** to create tasks (if available:
  `task.create`). Fall back to `TodoWrite` only if Task tools are not present
  in the current environment.

## Procedure

1. Run `board-status --json --ready-tasks 5` to get counts and up to 5 ready
   task objects without reading the full `board.json`.
2. Mirror up to **5** ready tasks from the `ready_tasks` array (the cap). For
   each, create a task entry with:
   - `title`: `#{number} {title}` for GitHub tasks, `[{id}] {title}` for local tasks.
   - `description`: URL and labels from the board entry.
   - `status`: `pending`
3. If `counts.ready` exceeds the length of `ready_tasks`, emit one compact
   summary line: `… and N more ready tasks (see board.json)` where
   `N = counts.ready - length(ready_tasks)`.
4. Do NOT create tasks for `blocked` or `needs-info` items — those must never
   be started without explicit user action.

## After running

Use `/board-run-ready` to dispatch ready tasks to cmux panes for parallel
execution.
