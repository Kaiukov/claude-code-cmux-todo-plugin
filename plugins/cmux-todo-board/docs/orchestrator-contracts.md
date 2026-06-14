# Orchestrator Contracts

## Naming contract
Use these fixed names:

- branch: `issue-<n>-<role>`
- worktree: `../wt-issue-<n>-<role>`
- tmux session: `orch-<n>-<role>`
- run id: `<n>-<role>-<ts>`
- run state: `.tasks/orchestrator/runs/<run-id>.json`
- log: `.tasks/orchestrator/logs/<run-id>.log`

## Portability contract
There are two roots: plugin assets stay resolved relative to the plugin install dir, while work and run state live in the TARGET/host repo. The orchestrator is portable across a portfolio: run it in any git project and it operates on that repo, not the plugin.

- TARGET repo resolution precedence: `ORCH_REPO_ROOT`, `--repo <path>` / `--repo-root <path>`, `git -C "$PWD" rev-parse --show-toplevel`.
- Worktrees are siblings of the TARGET repo: `<dirname TARGET>/wt-issue-<n>-<role>`.
- Run/log state lives in the TARGET repo: `<TARGET>/.tasks/orchestrator/{runs,logs}`.

## Run contract
Each run record must include:
- `run_id`
- `issue`
- `role`
- `worktree`
- `branch`
- `session`
- `started_at`
- `profile`

## Watcher contract
Watcher signals in V1:
- local `HEAD` change
- remote ref change/appearance
- worker process death

Statuses:
- `running`
- `progressed`
- `ready-for-verify`
- `failed`

Default timing:
- poll: `15s`
- stalled: `20m`
- timeout: `60m`

`stalled` means the session/process is alive, but neither local `HEAD` nor remote ref changed for 20 minutes.

## Completion contract
Progress means:
- a new local commit, or
- a push to the remote branch

Process exit is auxiliary. A process dying without git progress is a failure signal, not the main completion signal.

There is no printed sentinel in V1.

## Verify contract
The orchestrator verifies the result itself.
It must run the repo-level verify recipe and not trust worker self-report.

Verify only proceeds after a meaningful git result is observed.
Merge is out of scope for automation and only happens with explicit user confirmation.
