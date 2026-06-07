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
- **The task list is ephemeral.** These entries exist only for the current
  round. They disappear when the session ends.
- **Use the Task tools provider** to create tasks (if available:
  `task.create`). Fall back to `TodoWrite` only if Task tools are not present
  in the current environment.

## Procedure

1. Read `.tasks/board.json`.
2. Filter to tasks where `status == "ready"`.
3. For each ready task, create a task entry with:
   - `title`: `#{number} {title}` for GitHub tasks, `[{id}] {title}` for local tasks.
   - `description`: URL and labels from the board entry.
   - `status`: `pending`
4. Do NOT create tasks for `blocked` or `needs-info` items — those must never
   be started without explicit user action.

## After running

Use `/board-run-ready` to dispatch ready tasks to cmux panes for parallel
execution.
