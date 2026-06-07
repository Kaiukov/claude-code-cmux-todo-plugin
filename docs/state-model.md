# State Model

## Canonical Status Enum

The plugin uses a single canonical status enum across all representations:

`inbox` → `ready` → `in-progress` → `needs-review` → `blocked` | `needs-info` → `done`

Note: `blocked` and `needs-info` are terminal-without-completion states.
`done` replaces any legacy `completed` label.

## Four Representations

| Concern          | Representation                | Authority                     |
|------------------|-------------------------------|-------------------------------|
| STATUS           | GitHub Issue labels           | **Source of truth**           |
| Local cache      | `.tasks/board.json`           | Derived from issues + render  |
| Read-only view   | `TODO.md`                     | Regenerated, never hand-edited |
| Ephemeral plan   | Claude built-in task list     | Current round only; DISCARDED at round end |

## Mapping Table

| GitHub label    | board.json `status` | Claude task state |
|-----------------|---------------------|--------------------|
| `inbox`         | `inbox`             | `pending`          |
| `ready`         | `ready`             | `pending`          |
| `in-progress`   | `in-progress`       | `in_progress`      |
| `needs-review`  | `needs-review`      | `pending`          |
| `blocked`       | `blocked`           | `pending`          |
| `needs-info`    | `needs-info`        | `pending`          |
| `done`          | `done`              | `completed`        |
| `completed`     | `done`              | `completed`        |

When an issue has multiple status labels, the **most-progressed** status wins
(last match in canonical order: `done` > `needs-info`/`blocked` > `needs-review`
> `in-progress` > `ready` > `inbox`). The legacy `completed` label is treated as
equivalent to `done`.

## Session Recovery

Claude's built-in task list is ephemeral — it is discarded at the end of every round.
On session start or after a lost session:

1. Run `board-pull` to refresh `.tasks/issues.json` from GitHub labels.
2. Run `board-render` to regenerate `.tasks/board.json` and `TODO.md`.
3. Run `board-plan` to mirror only `ready` tasks into the built-in task list.
4. Status is re-read from GitHub labels — no local state is trusted across sessions.

## Concurrency Rule

Only ONE task may be marked `in_progress` in the orchestrator's built-in task list.
Real parallelism is managed by cmux pane state, not the task list.
