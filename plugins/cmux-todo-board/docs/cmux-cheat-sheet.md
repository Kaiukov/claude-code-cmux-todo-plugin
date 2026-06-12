# cmux Cheat Sheet — Notify / Feed / Events

## Primitives

| Command | Flags | Purpose |
|---|---|---|
| `cmux notify` | `--title <t> [--subtitle <s>] [--body <b>] [--surface\|--workspace\|--window <ref>]` | Send a notification to a pane or workspace; appears in the cmux UI and event stream |
| `cmux hooks <agent> install` | `cmux hooks opencode install [--feed] [--project]`, `cmux hooks codex install` | Install lifecycle (`cmux-session.js`) and feed (`cmux-feed.js`) hook plugins for the given agent backend. Idempotent; run once per machine |
| `cmux feed` | `cmux feed tui [--opentui\|--legacy]`, `cmux feed clear [-y]` | Interactive feed TUI for approvals/questions. No programmatic output — use `cmux events --category feed` to consume in scripts |
| `cmux events` | `--category agent\|notification\|feed [--no-heartbeat] [--cursor-file <path>]` | Stream NDJSON events from cmux. Key categories: `agent` (lifecycle), `notification` (notify payloads), `feed` (approvals) |

### Other useful primitives

| Command | Purpose |
|---|---|
| `cmux list-notifications` | List queued notifications |
| `cmux dismiss-notification --id <uuid> \| --all-read` | Dismiss notifications |
| `cmux mark-notification-read --id <uuid> \| --workspace \| --all` | Mark notifications as read |
| `cmux set-status <key> <value> [--workspace] [--surface]` | Update surface status bar |
| `cmux set-progress <0.0-1.0> [--label <t>] [--workspace]` | Workspace progress bar |
| `cmux wait-for [-S] <name> [--timeout <s>]` | tmux-compat named sync barrier |
| `cmux log [--level] [--source] <msg>` | Emit structured log entry |

## Per-Backend Setup

| Backend | Install | Completion Signal |
|---|---|---|
| Claude Code | Wrapper-managed; enabled via cmux settings | `cmux notify --title CTB-DONE --body "task=… surface=… status=… branch=…" --surface <ref>` |
| Codex | `cmux hooks codex install` | `CTB-DONE` notify (explicit) or `cmux events --category notification` (stream) |
| OpenCode | `cmux hooks opencode install` (add `--feed` for approvals) | `agent.hook.idle` lifecycle (automatic, via `cmux-session.js`) or `CTB-DONE` notify (explicit) |

## Agent Completion Signal

```bash
cmux notify --title "CTB-DONE" \
  --body "task=82 surface=surface:172 status=success branch=docs/82-cmux-cheat-sheet" \
  --surface "surface:172"
```

Agent calls this as its final step (`agent-notify.sh` wraps it with structured payload). Also works as bare positional: `cmux notify "CTB-DONE task=…"` (legacy).

## Orchestrator Wait Flow

```
agent-notify.sh (CTB-DONE notify) ─┐
                                   ├──► cmux event stream
cmux-session.js (agent.hook.idle) ─┘
                                          │
                                          ▼
  poll-wait.sh --surface <ref> --branch <name> [--task <id>]
         │
         ├─ PRIMARY: cmux events --category agent --category notification --no-heartbeat
         │     grep -E "(lifecycle.*idle|hook_event_name.*Stop|CTB-DONE)"
         │     → COMPLETE method=event
         │
         └─ FALLBACK: poll-push.sh <branch> 60 <total-timeout>
               git ls-remote polling every 60 s
               → COMPLETE method=poll | TIMEOUT
```

- `poll-wait.sh` is a bash-native dual-source waiter (no GNU `timeout` dependency).
- If `cmux` is not available, degrades gracefully to poll-only.
- Standby rule: orchestrator waits on `poll-wait.sh` — never screen-scrapes or types into a working agent pane.

## See Also

- [Agent Notifications](agent-notifications.md) — per-backend completion paths & reliability matrix
- [Orchestrator Rules](ORCHESTRATOR.md) — delegation cycle & standby-after-dispatch rule
- [Codex Port](codex-port.md) — Codex adapter, backend routing & completion loop
- [Event-Driven Design](research/cmux-notify-feed-orchestrator.md) — full design doc for `poll-wait.sh`
