# Agent Completion Notifications

**Status:** IMPLEMENTED — event-driven `poll-wait.sh` (PRIMARY) + `poll-push.sh` fallback.

## cmux primitives

| Primitive | Carries event? | Notes |
|-----------|---------------|-------|
| `cmux notify` | Yes — direct notification to the orchestrator pane. | Lightest path; can carry structured payload (issue#, branch, success/failure). |
| `cmux hooks <agent> install --feed` | Yes — hook feed from agent pane. | Good for richer lifecycle events (start, progress, done, error). |
| `cmux set-status` / `cmux set-progress` | Partial — updates cmux pane status bar. | Visible to orchestrator but not a dedicated event; best combined with `notify`. |

## Per-backend reliability

### pi (primary runtime)
The pi agent emits completion via the cmux notification stream.
Use `cmux notify` from the agent's final command as the
application-level signal, with `poll-push.sh` as polling backup.

### claude (Anthropic Claude Code)
No native completion event. Same fallback pattern: `cmux notify` as the
primary application-level signal, with pane-output polling as the
backstop. The `--feed` hook mechanism can be used if hooks are
installed in the agent session.

## Recommended flow

```
Agent finishes  →  cmux notify orchestrator (explicit CTB-DONE, structured flags)
                               ↓
                    cmux-session.js emits agent.hook.Stop (automatic lifecycle)
                               ↓
                    poll-wait.sh detects either signal via cmux events stream
                               ↓
                    orchestrator marks task complete
                               ↓
               if no event within timeout → poll-push.sh fallback (git polling)
```

The fallback window should be generous enough to avoid false timeouts
but short enough that no task is stranded indefinitely.

## Backend matrix

| Backend | Setup | Completion / notification path | Feed path |
|---|---|---|---|
| Claude Code | Wrapper-managed; enabled through cmux settings | `cmux notify --title "CTB-DONE" --body "..." --surface <surface>` from the agent's final step, then observe `cmux events --category notification` / `--category agent` | Wrapper-injected `PermissionRequest` only; use `cmux feed tui` to approve from the sidebar when a request appears |
| Pi | `pi` binary on PATH | Same `cmux notify` completion signal; `poll-wait.sh` listens for `CTB-DONE` and agent idle events | `cmux hooks pi install` — Pi notifications surface through the Feed / notification flow |

Practical rule:

- Use `cmux notify` for one-way completion or alert messages.
- Use `cmux feed tui` when the agent is blocked on permission, plan-mode, or a question.
- Use `cmux events --category notification --category agent --category feed` when you want to automate against the stream instead of reading the UI.
