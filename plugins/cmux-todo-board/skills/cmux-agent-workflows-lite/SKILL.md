---
name: cmux-agent-workflows-lite
description: Default delegation reference — compact delegation cycle, script table, and model profiles for routine sessions. For advanced topics (backends, hooks install, live-deploy traps), use cmux-agent-workflows.
---

# cmux-agent-workflows-lite

**Full reference:** `skills/cmux-agent-workflows/SKILL.md` (backends, hooks install, live-deploy traps, codex gotchas).

## Default dispatch

The primary flow is headless `pi -p` background workers. The parked 3×3 cmux dashboard is optional watch/intervene only.

```bash
S=skills/cmux-agent-workflows/scripts
WT=$($S/wt-new.sh feat/foo ../wt-feat-foo)          # 1. worktree
cd "$WT" && pi -p --mode json -a \
  --provider <p> --model <m> --tools <...> \
  --append-system-prompt prompts/pi/roles/<role>.md @"$WT"/.task-spec.md > out.json 2>&1 &
# 2. headless worker (completion = exit code + CTB-DONE + branch commit)
$S/verify.sh "$WT"                                  # 3. gate
$S/pr-finish.sh 42 "$WT"                            # 4. merge
# 5. optional dashboard only: agent-audit.sh / agent-screen.sh / agent-notify.sh / poll-wait.sh / poll-push.sh
```

Model profiles: `backend`, `backend-fast`, `repo-scout`, `docs`, `test`, `tiny-patch`, `review`, `frontend`, `frontend-top` — resolved via `board-config --get-profile <name>`.
