# coms-net Design: Structured Event Bus for Pi Worker Completion

## Problem

The orchestrator currently detects Pi worker completion via two brittle mechanisms:

1. **Screen-scraping the agent pane** — watching terminal output for completion
   signals is fragile, reflow-sensitive, and couples the orchestrator to the
   TUI layout.

2. **Git-polling** (`poll-push.sh` / `poll-wait.sh`) — polling `origin/<branch>`
   for new commits. This works but adds latency (sleep intervals), remote
   dependency (network to GitHub), and wastes CI minutes.

The POC criterion is that _"completion requires polling the pane"_. The
orchestrator should receive a structured completion signal without parsing
terminal output or waiting for a remote git push.

## Solution: coms-net Event Bus

coms-net is a **structured event bus** consisting of:

- A **Bun HTTP/SSE hub** (`scripts/coms-net-server.ts`) that stores and
  routes events with auth, TTL, channel isolation, heartbeat, and max-hops.
- A **Pi worker extension** (`.pi/extensions/coms-net.ts`) that emits a
  `type: "done"` event on `agent_end` (natural completion).
- An **orchestrator-side bash helper** (`coms-net-await.sh`) that blocks
  until the `done` event arrives, printing the event JSON and exiting 0.
- **Git-poll as a non-destructive fallback**: when the hub is unreachable or
  the await times out, the helper exits non-zero and the orchestrator falls
  through to git-poll.

```
┌──────────────┐     POST /send        ┌──────────────────┐     GET /await      ┌───────────────┐
│  Pi Worker   │ ────────────────────► │  coms-net Hub    │ ◄─────────────────── │ Orchestrator  │
│ (extension)  │   {type:"done",...}   │  (Bun SSE/HTTP)  │   block until done  │ (await.sh)    │
└──────────────┘                       └──────────────────┘                      └───────────────┘
                                              │
                                        (in-memory store)
                                        auth-token / TTL
                                        channel isolation
                                        heartbeat / max-hops
```

## Hub Architecture

### Endpoints

| Method | Path      | Purpose                                                |
|--------|-----------|--------------------------------------------------------|
| POST   | `/send`   | Enqueue an event (channel-isolated, TTL-gated)         |
| GET    | `/get`    | Retrieve the next matching event without blocking      |
| GET    | `/await`  | Block (SSE or poll) until a matching event arrives     |
| GET    | `/list`   | List all active events for a channel                   |
| GET    | `/health` | Liveness probe                                         |

### SSE vs Poll

The hub supports two `/await` modes:

- **SSE** (`poll=0`, default) — Server-Sent Events stream with heartbeats.
  Suitable for long-lived connections from Node.js/Bun clients.
- **Poll** (`poll=1`) — HTTP long-poll with retries at 1s intervals.
  Suitable for bash/curl clients (`coms-net-await.sh`) that cannot consume
  SSE streams reliably.

The bash helper uses poll mode for maximum compatibility (no persistent TCP
connection management needed in bash).

### In-Memory Store

Events live in an in-memory `Map` keyed by event ID. A periodic sweep
(every 30s) removes events that have exceeded their TTL. Awaiters are
registered per-channel and notified when a matching event arrives.

## Message Schema

### Completion Event (`type: "done"`)

```json
{
  "type": "done",
  "channel": "/path/to/worker/worktree",
  "branch": "feat/comsnet-92",
  "status": "success",
  "ts": 1718234567890
}
```

Fields:
- `type` (string) — always `"done"` for completion events.
- `channel` (string) — channel key (worker cwd path or `COMS_NET_CHANNEL`).
- `branch` (string) — git branch the worker was operating on.
- `status` (string) — `"success"` or `"failure"`.
- `ts` (number) — Unix milliseconds timestamp.

Additional fields MAY be present but these 5 are the minimum contract.

### Generic Event

```json
{
  "type": "progress",
  "channel": "/path/to/worker/worktree",
  "message": "Linting complete...",
  "ts": 1718234561000
}
```

## Auth & Security

### Token

Every request MUST carry an `Authorization: Bearer <token>` header. The
token is set via the `COMS_NET_TOKEN` environment variable on the hub,
workers, and orchestrator.

- The token is **never hardcoded** in any source file.
- Without a matching token, the hub returns `401 Unauthorized`.
- The hub refuses to start if `COMS_NET_TOKEN` is not set.

### Channel Isolation

Events are namespaced by a **channel key**. Two workers with different
channels cannot see or consume each other's events. The channel defaults to
the worker's `cwd` (worktree path), but can be overridden with
`COMS_NET_CHANNEL`. This prevents cross-project leakage and ensures the
orchestrator only receives completion for the worker it dispatched.

### TTL

Events expire after `COMS_NET_TTL_SEC` seconds (default 300). Expired events
are removed by a background sweep (every 30s). This prevents stale events
from accumulating in memory.

### Max-Hops

`COMS_NET_MAX_HOPS` (default 100) limits the number of concurrent `/await`
clients per channel. When exceeded, new awaiiters receive an error. This
prevents resource exhaustion from leaked connections.

### Heartbeat

SSE connections receive a heartbeat event every `COMS_NET_HEARTBEAT_SEC`
seconds (default 15). This keeps the connection alive through proxies and
allows clients to detect a dead connection.

## Completion Contract

1. **Worker emits** — When a Pi worker's agent loop ends (`agent_end` event),
   the `coms-net.ts` extension POSTs a `done` event to
   `{hub}/send?channel={cwd}`. `status` is `"success"` (agent_end means
   natural completion; worker-detected failure would emit `"failure"`).

2. **Orchestrator awaits** — After spawning a worker, the orchestrator calls
   `coms-net-await.sh --channel {worktree} --timeout 120`. The script blocks
   until it receives a `done` event, prints the JSON, and exits 0.

3. **Fallback** — If the hub is unreachable (health check fails) or the await
   times out, `coms-net-await.sh` exits non-zero. The orchestrator falls
   through to the existing git-poll path (`poll-wait.sh` / `poll-push.sh`).

## Git-Poll Fallback

`poll-push.sh` and `poll-wait.sh` are **NOT modified or disabled**. They
remain as the documented, tested fallback. The fallback triggers when:

- The coms-net hub is not running (health check returns non-200).
- The `COMS_NET_TOKEN` is not set.
- The await times out (worker crashed before emitting, network issues).
- curl fails to parse the response.

In all these cases, `coms-net-await.sh` exits non-zero and the orchestrator
calls the git-poll path as before.

## Integration Contract (for the Orchestrator)

The orchestrator integrates coms-net in a later step (out of scope for this
deliverable). The contract is:

### Prerequisites

1. **Bun** must be available to run the hub server.
2. The hub server is started once per orchestrator session:
   ```bash
   COMS_NET_TOKEN="shared-secret" \
   COMS_NET_PORT=9876 \
     bun run scripts/coms-net-server.ts &
   ```
3. At worker spawn, set environment variables:
   ```bash
   COMS_NET_HUB_URL="http://127.0.0.1:9876"
   COMS_NET_TOKEN="shared-secret"
   COMS_NET_CHANNEL="/path/to/worker/worktree"   # or let it default to cwd
   COMS_NET_BRANCH="feat/comsnet-92"
   ```

### Awaiting Completion

After spawning the worker, the orchestrator calls:

```bash
COMS_NET_TOKEN="shared-secret" \
  coms-net-await.sh \
    --channel "/path/to/worker/worktree" \
    --timeout 120 \
    --hub "http://127.0.0.1:9876"
```

Exit codes:
- `0` — Event received; JSON printed to stdout.
- `1` — (reserved).
- `2` — `COMS_NET_TOKEN` not set.
- `3` — Hub unreachable (health check failed).
- `4` — Timeout or no response from hub.
- `5` — Invalid JSON response.

On any non-zero exit, the orchestrator falls back to git-poll:

```bash
if coms-net-await.sh ... ; then
  echo "coms-net: worker completed"
else
  echo "coms-net: unavailable, falling back to git-poll"
  poll-wait.sh --surface ... --branch ... --cwd ...
fi
```

### No Modifications to Existing Code

`lib.sh`, `agent-spawn.sh`, `board-config`, `poll-push.sh`, and
`poll-wait.sh` are **not modified** in this task. The wiring/adoption is a
separate orchestrator step.

## Files Delivered

| File | Purpose |
|------|---------|
| `scripts/coms-net-server.ts` | Bun HTTP/SSE hub |
| `.pi/extensions/coms-net.ts` | Pi worker extension (emit + tools) |
| `plugins/.../scripts/coms-net-await.sh` | Orchestrator bash helper |
| `docs/coms-net-design.md` | This design doc |
| `plugins/.../tests/test_coms_net.sh` | Bash tests |

## License

Ported from [disler/pi-vs-claude-code](https://github.com/disler/pi-vs-claude-code)
under the MIT license. Attribution headers are included in each ported file.
