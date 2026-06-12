---
name: cmux-agent-workflows-lite
description: Default delegation reference — compact delegation cycle, script table, and model tiers for routine sessions. For advanced topics (backends, hooks install, codex gotchas, live-deploy traps), use cmux-agent-workflows.
---

# cmux-agent-workflows-lite

**Full reference:** `skills/cmux-agent-workflows/SKILL.md` (backends, hooks install, live-deploy traps, codex gotchas).

## Scripts (`skills/cmux-agent-workflows/scripts/`)

| Script | Purpose |
|--------|---------|
| `wt-new.sh` | New worktree from origin/main + .env + bun install |
| `agent-spawn.sh` | Split pane, boot agent, wait ready, echo surface ref |
| `agent-send.sh` | Send prompt + Enter to agent surface |
| `agent-screen.sh` | Read agent surface screen |
| `agent-kill.sh` | Kill agent proc by tty, optionally close split |
| `agent-notify.sh` | Agent final step: emit CTB-DONE payload |
| `poll-wait.sh` | PRIMARY wait: cmux events + git-poll fallback |
| `poll-push.sh` | FALLBACK git-poll: polls origin until branch pushed |
| `verify.sh` | Project-agnostic gate (bash -n + test) |
| `verify-ts.sh` | TS hard gate (typecheck + bun test) |
| `pr-finish.sh` | Remove worktree, squash-merge, delete branch |
| `agent-audit.sh` | Audit agent session logs |
| `lib.sh` | Shared helpers (sourced by others) |

## Standard delegation cycle

```bash
S=skills/cmux-agent-workflows/scripts
WT=$($S/wt-new.sh feat/foo ../wt-feat-foo)          # 1. worktree
SURF=$($S/agent-spawn.sh right "$WT" <model> TASK)  # 2. spawn agent
$S/agent-send.sh "$SURF" < dispatch-prompt.txt      # 3. dispatch
$S/poll-wait.sh --surface "$SURF" --branch feat/foo # 4. wait
$S/verify.sh "$WT"                                   # 5. gate
$S/pr-finish.sh 42 "$WT"                             # 6. merge
$S/agent-kill.sh "$SURF" --agent pi --close    # 7. cleanup
```

Model tiers: `flash`, `pro`, `review`, `simple`, `top` — resolved via `.tasks/config.json`.
