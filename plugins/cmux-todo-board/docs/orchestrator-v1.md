# Orchestrator V1

## What V1 can do
V1 is the happy-path loop:

1. take a GitHub issue
2. create branch + worktree
3. start a worker in `tmux` via `pi`
4. wait for commit/push progress
5. wake the orchestrator
6. run repo verify
7. return a short summary and next step

V1 is built for one active worker session per issue.

## What V1 does not do
- no auto-merge
- no deploy automation
- no required PR
- no CI/review/webhook wake path
- no reliance on worker self-report
- no non-`pi` single-worker runtime in V1
- no broad role set

V1 roles are limited to:
- `repo-scout`
- `backend`
- `reviewer`

## V1 bin entrypoints
- `orch-config` — resolve profile config by role
- `orch-dispatch` — accept `issue + role`, trigger spawn, return run status
- `orch-spawn` — resolve the host repo (`ORCH_REPO_ROOT`/`--repo`/cwd), create a sibling worktree, session, and run state, then launch the worker
- `orch-watch` — watch git/tmux signals and wake on progress
- `orch-status` — show a compact snapshot of active runs
- `orch-verify` — run the repo-level verify recipe for the current run
- `orch-finish` — close the run and clean local runtime state

## Operational shape
The V1 loop is intentionally small:
issue → worktree/branch → tmux pi worker → commit/push → wake → verify → summary.

The orchestrator treats git signals as the real progress signal, not pane noise.
V1 is portable: run it inside any git repo and it operates on that repo, not the plugin.
