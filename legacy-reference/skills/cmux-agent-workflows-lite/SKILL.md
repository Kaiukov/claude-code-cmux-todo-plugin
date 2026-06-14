---
name: cmux-agent-workflows-lite
description: Default delegation reference — compact headless dispatch cycle and model profiles for routine sessions. For advanced topics (backends, hooks install, live-deploy traps), use cmux-agent-workflows.
---

# cmux-agent-workflows-lite

**Full reference:** `skills/cmux-agent-workflows/SKILL.md` (backends, hooks install, live-deploy traps, codex gotchas).

## Default dispatch

The primary flow is headless `pi` background workers.

```bash
S=skills/cmux-agent-workflows/scripts
WT=$($S/wt-new.sh feat/foo ../wt-feat-foo)
PID=$($S/worker-spawn.sh "$WT" --profile backend 42)
$S/worker-watch.sh --pid "$PID" --out "$WT/out.json" --worktree "$WT"
$S/verify.sh "$WT"
$S/pr-finish.sh 42 "$WT"
```

- `worker-spawn.sh` echoes the worker PID.
- `worker-watch.sh` is the canonical waiter / liveness watchdog.
- Completion = worker exit code + a new commit on the branch (git progress) + branch commit.

Model profiles: `backend`, `backend-fast`, `repo-scout`, `docs`, `test`, `tiny-patch`, `review`, `frontend`, `frontend-top` — resolved via `board-config --get-profile <name>`.
