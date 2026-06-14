---
name: board
description: Main board skill — describes the overall plugin flow, sources of truth, and operating rules.
---

# Board Skill

The `cmux-todo-board` plugin bridges GitHub Issues into a local task board and
mirrors ready tasks into Claude's built-in task list for the current round.

## Sources of Truth

- **GitHub Issue labels** = source of truth for STATUS.
- **`.tasks/board.json`** = local cache (derived from issues + render).
- **`TODO.md`** = read-only human-readable render. Never hand-edit.
- **Claude built-in task list** = ephemeral plan for the current round only.
  It is DISCARDED at round end and is never authoritative.

## Operating Rules

1. **Never start blocked or needs-info tasks.** Skip `blocked` and `needs-info` items.
2. **One in_progress only.** Keep at most ONE task `in_progress` in the
   orchestrator's built-in task list. Real parallelism is the count of live
   headless `pi` worker processes, not the task list.
3. **Status lives in GitHub labels.** When a round ends, the built-in task list
   disappears. Status is re-read from GitHub on the next `board-pull`.
4. **Task list is a plan, not a database.** The built-in task list is for
   orchestrating the current round. Do not attempt to persist state in it.

## Canonical Status Order

`inbox` → `ready` → `in-progress` → `needs-review` → `blocked` | `needs-info` → `done`

## Workflow

1. **Pull:** `/board-pull` fetches issues from GitHub and renders the board.
2. **Read:** Review `TODO.md` or `board.json` to see all tasks.
3. **Select:** Identify `ready` tasks that can be worked on this round.
4. **Plan:** `/board-plan` mirrors `ready` tasks into Claude's built-in task list.
5. **Dispatch:** `/board-run-ready` dispatches ready tasks to headless `pi`
   workers (cap: 2; parked 3×3 dashboard optional watch/intervene only).
