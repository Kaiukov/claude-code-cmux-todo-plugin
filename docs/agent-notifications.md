# Agent Completion Notifications

**Status:** IMPLEMENTED — `agent-notify.sh` + `poll-push.sh` fallback.

## cmux primitives

| Primitive | Carries event? | Notes |
|-----------|---------------|-------|
| `cmux notify` | Yes — direct notification to the orchestrator pane. | Lightest path; can carry structured payload (issue#, branch, success/failure). |
| `cmux hooks <agent> install --feed` | Yes — hook feed from agent pane. | Good for richer lifecycle events (start, progress, done, error). |
| `cmux set-status` / `cmux set-progress` | Partial — updates cmux pane status bar. | Visible to orchestrator but not a dedicated event; best combined with `notify`. |

## Per-backend reliability

### codex (OpenAI Codex CLI)
Native `PreToolUse` / `PermissionRequest` hooks are the most reliable
completion signal. The agent can emit a hook before its final tool use
or on session close. No polling needed if hooks are configured.

### opencode
No native completion event. Fallback: poll the pane for terminal output
or use `cmux notify` from the agent's final command. Screen-scraping
the pane is possible but fragile; prefer `cmux notify` as the
application-level signal with polling as backup.

### claude (Anthropic Claude Code)
No native completion event. Same fallback pattern: `cmux notify` as the
primary application-level signal, with pane-output polling as the
backstop. The `--feed` hook mechanism can be used if hooks are
installed in the agent session.

## Recommended flow

```
Agent finishes  →  cmux notify orchestrator (primary, carries payload)
                              ↓
                   orchestrator marks task complete
                              ↓
              if no event within timeout → poll-push.sh (fallback)
```

The fallback window should be generous enough to avoid false timeouts
but short enough that no task is stranded indefinitely.
