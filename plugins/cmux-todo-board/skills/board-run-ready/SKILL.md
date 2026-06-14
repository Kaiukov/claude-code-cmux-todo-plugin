---
name: board-run-ready
description: Dispatch ready tasks into headless pi workers for parallel execution.
---

# board-run-ready

Dispatches ready tasks from `.tasks/board.json` into headless `pi -p` background workers for parallel agent execution. The parked 3×3 cmux cockpit is optional watch/intervene only.

## Prerequisites

- `.tasks/board.json` exists — run `/board-pull` first.
- `pi` on PATH. The cmux dashboard helpers are optional and not part of the default path.

## Pick work

Use compact helpers, not a full board read:
- `bin/board-status` → status counts + next ready (one line).
- `bin/board-next --json` → next ready task object.

## Concurrency

- Cap: 2 active background workers.
- At most ONE task `in_progress` in the built-in task list.
- Live worker process count is the real tracker; other dispatched tasks stay `pending`.

## Dispatch

For the routine delegation workflow (worktree → headless `pi -p` spawn → dispatch → standby), see `orchestrator-dispatch` / `bin/orch-dispatch`. The sections below cover the run-ready–specific dispatch flow.

### Step 0: Generate `.task-spec.md`

Before spawning a worker, generate a maximally detailed `.task-spec.md` inside the worker
worktree (`<worktree>/.task-spec.md`). Never place it in `/tmp` or external
directories. Fill every placeholder (`<...>`) with task-specific values:

```markdown
# Task: #<N> <title>

GitHub: <url>

## Goal (one-liner)
<single-sentence summary of what needs to be done>

## Scope
- **PRIMARY:** <file-spec> — <what to change/add>
- **SECONDARY:** <file-spec> — <what to change/add>
- **DO NOT TOUCH:** <off-limits-files-or-dirs>

## Files
Exact repo-relative paths to create or modify:
- `<path/to/file1>` — <create|modify>
- `<path/to/file2>` — <create|modify>

## Verification
Run before declaring done:
- `bash plugins/cmux-todo-board/tests/test_*.sh` — must pass: <N>/<N>
- `<additional-check-command>`

## Commit instructions
- Branch: `<branch-name>`
- Commit message: `<type>: <description> (<task-id>)`
- Push: `git push origin <branch>`

## Acceptance criteria
- [ ] <verifiable condition>
- [ ] All tests pass
- [ ] Node/typecheck pass (where applicable)

## CHANGELOG
Add an entry under `CHANGELOG.md`'s `## [Unreleased]` using the correct
Keep-a-Changelog subsection (`### Added`, `### Changed`, `### Fixed`, etc.)
that matches the type of change. Reference this task id in the entry.

## forbidden_reads
- `.tasks/issues/*` — do NOT glob-read materialised issue bodies.
- `<additional restricted path, if any>`
```

All five sections (`Scope` with boundaries, `Files`, `Verification`, `Commit instructions`,
`forbidden_reads`) are required. The orchestrator fills each with concrete values per task.

### Steps 1–8

See the [canonical delegation cycle in `docs/ORCHESTRATOR.md`](../../docs/ORCHESTRATOR.md#headless-delegation-cycle). The scripts at `skills/cmux-agent-workflows/scripts/` map one-to-one to the steps there. Only the procedural loop is shared — all board-run-ready–specific constraints (below) still apply.

## Merge gate (user confirmation)

After verification passes, `pr-finish.sh` prompts `Merge PR #N? (y/N)` and only proceeds on explicit `y`/`yes`. The non-interactive default is safe — piping `n` or empty input aborts without merging. The orchestrator must never bypass or automate this prompt.

## Verification (hard gate)

Never trust an agent's self-report. Run the project's tests **and**
`claude plugin validate .`. Both must pass before marking `completed`.

## Completion notification flow

- **PRIMARY:** completion is the worker process exit code plus a new commit on the branch (git progress) and the worker's branch commit.
- **HEADLESS standby:** `worker-watch.sh --pid <PID> --out <WT>/out.json --worktree <WT>` is the canonical waiter for the default path.
- No dashboard helpers are needed for the default path.

## Standby after dispatch

After dispatching, wait on the worker process exit-code callback, a new commit on the branch (git progress), and the branch commit. No active polling in the default path.

## MVP note

Status is NOT written back to GitHub labels. That is #5 sync-back.

## Fallback (no cmux)

List ready tasks via `bin/board-status` / `bin/board-next` for manual dispatch.
