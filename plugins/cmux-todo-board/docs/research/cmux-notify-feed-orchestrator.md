# cmux notify+feed orchestrator — design doc

## 1. Current state

### 1.1 How `poll-push.sh` works

`skills/cmux-agent-workflows/scripts/poll-push.sh` (43 lines) is a blocking polling loop:

1. Capture `git ls-remote origin <branch>` as a baseline SHA.
2. If the branch already has commits ahead of `origin/main` on origin, report `PUSHED` immediately and exit (commit 922c9ad added this early-exit).
3. Otherwise, **loop**: `sleep 30` → `git ls-remote origin <branch>` → compare SHA. Repeat until SHA changes or the 1800 s timeout expires.

The orchestrator runs it via `Bash run_in_background:true` so it does not block the orchestrator's own conversation loop. On completion, the background task notification alerts the orchestrator.

**Cost:**
- **Blocks the orchestrator's attention** — while the background poll-push runs, the orchestrator has no structured signal that a specific agent finished; it relies on the harness's background-task notification.
- **30 s polling interval** — worst-case 30 s of wasted latency after agent push.
- **1800 s timeout** — if no push occurs, stranded for 30 minutes.
- **Network I/O every interval** — `git ls-remote` hits the remote every 30 s regardless of whether the agent is still working.
- **No awareness of agent completion** — the script sees only a git push, not that the agent finished its work (finished but didn't push = timeout).

### 1.2 What #38 (commit 922c9ad) already wired up

Commit `922c9ad` ("event-driven agent completion notify + poll-fallback fix") introduced `agent-notify.sh` as the agent's FINAL step.

**`agent-notify.sh`** (40 lines):
- Formats a `CTB-DONE` payload: `CTB-DONE task=<id> surface=<ref> status=success|failure [branch=<name>]`
- Calls `cmux notify "$PAYLOAD"` (PRIMARY path) or echoes the payload to stdout (FALLBACK).
- Is intended to be called by the agent itself as its last action before exiting.

**What #38 did NOT do:**
- The orchestrator does not listen to `cmux notify` nor `cmux events` — it still runs `poll-push.sh` as the **sole** completion detector.
- `agent-notify.sh` and `poll-push.sh` are disconnected: `poll-push.sh` waits for a git push, `agent-notify.sh` emits a cmux notification — but nothing bridges the two.
- The SKILL.md and docs reference "PRIMARY event-driven / FALLBACK poll" but the orchestrator loop never subscribes to events.

**Bug in `agent-notify.sh`:**
Line 36 calls `cmux notify "$PAYLOAD"` passing the entire CTB-DONE string as a single positional argument. Per `cmux --help`, `cmux notify` expects structured flags:
```
cmux notify --title <text> [--subtitle <text>] [--body <text>] [--workspace/surface/window]
```
The positional arg may be accepted as the title implicitly, but this is unreliable and does not set `--body`, `--subtitle`, or a target surface. This should be fixed to:
```bash
cmux notify --title "CTB-DONE" --body "task=$TASK surface=$SURFACE status=$STATUS branch=${BRANCH:-}" --surface "$SURFACE"
```

## 2. cmux primitives (verified)

All commands verified via `cmux --help` and `cmux hooks --help` output on macOS / cmux CLI, except where marked UNVERIFIED.

### 2.1 Notification commands

| Command | Verified? | Output shape | Notes |
|---|---|---|---|
| `cmux notify --title <t> [--subtitle <s>] [--body <b>] [--workspace] [--surface] [--window]` | Confirmed via `cmux --help` | No stdout; notification appears in cmux UI + events stream | Lightest-path application signal. Can target a specific surface. |
| `cmux list-notifications` | Confirmed via `cmux --help` | Lists queued notifications (JSON format UNVERIFIED) | Could be polled as lightweight alternative to git ls-remote |
| `cmux dismiss-notification (--id <uuid> \| --all-read)` | Confirmed via `cmux --help` | — | Cleanup after ack |
| `cmux mark-notification-read (--id <uuid> \| --workspace \| --all)` | Confirmed via `cmux --help` | — | Programmatic ack |

### 2.2 Event stream

| Command | Verified? | Output shape | Notes |
|---|---|---|---|
| `cmux events [--category <name>] [--name <name>] [--no-heartbeat] [--reconnect] [--cursor-file <path>]` | Confirmed via `cmux --help` and documented in `WAIT_WITHOUT_SLEEP.md` | Newline-delimited JSON (NDJSON) | **The key primitive.** Streams all cmux events. Categories include `agent`, `feed`, `notification`, `window`, `workspace`, `pane`, `surface`. Filter by `--category notification` for notify events, `--category agent` for lifecycle. |
| Event shape (from WAIT_WITHOUT_SLEEP.md) | Documented, NOT directly verified | `{name, category, surface_id, payload: {lifecycle}}` | Agent lifecycle events carry `lifecycle: "running" \| "idle" \| "needsInput"`. |

### 2.3 Agent lifecycle events (via opencode plugins)

| Plugin file | Source | Effect | Verified? |
|---|---|---|---|
| `~/.config/opencode/plugins/cmux-session.js` | Installed by `cmux hooks opencode install` | Emits `agent.hook.*` events: `running`, `idle`, `needsInput` lifecycle states | Documented in `WAIT_WITHOUT_SLEEP.md`; plugin existence verifiable via `ls ~/.config/opencode/plugins/`. Event names and exact payload structures are **UNVERIFIED** (would require a live agent session + `cmux events --category agent` capture). |
| `~/.config/opencode/plugins/cmux-feed.js` | Installed by `cmux hooks opencode install --feed` | Emits `feed.item.received` for approvals, questions, telemetry | Same as above — **UNVERIFIED** event shapes. |

Installation (idempotent, one-time per machine):
```bash
yes | cmux hooks opencode install            # session plugin
yes | cmux hooks opencode install --feed     # feed plugin
```

Opencode agents started BEFORE plugin installation do NOT emit events; respawn required.

### 2.4 Feed mechanism

| Command | Verified? | Output shape | Notes |
|---|---|---|---|
| `cmux feed tui [--opentui\|--legacy]` | Confirmed via `cmux --help` | Interactive TUI | Opens the keyboard-first Feed TUI. UI-only, not programmatic. |
| `cmux feed clear [--yes\|-y]` | Confirmed via `cmux --help` | — | Clears persisted feed workstream history. |
| `cmux hooks feed --source <agent> [--event <event>]` | Confirmed via `cmux --help` | "Internal Feed decision bridge" | Used by hooks infra, not invoked directly by orchestrator scripts. |

**Key finding:** `cmux feed` has NO programmatic output (no `--json`, no `list`). The Feed is a UI concept. For programmatic consumption, use `cmux events --category feed` instead.

### 2.5 Synchronization primitives

| Command | Verified? | Notes |
|---|---|---|
| `cmux wait-for [-S\|--signal] <name> [--timeout <s>]` | Confirmed via `cmux --help` | tmux-compat named sync tokens. Signal (`-S`) from one side, wait from another. Could be used for agent→orchestrator coordination. Default timeout 30 s. |
| `cmux set-hook <event> <command>` | Confirmed via `cmux --help` | tmux-compat hook system. UNVERIFIED which events are triggerable (likely session events only). |

### 2.6 Status / progress (auxiliary)

| Command | Verified? | Notes |
|---|---|---|
| `cmux set-status <key> <value> [--workspace] [--surface]` | Confirmed via `cmux --help` | Updates status bar of a surface. Visible but not an event. |
| `cmux set-progress <0.0-1.0> [--label <t>] [--workspace]` | Confirmed via `cmux --help` | Progress bar on workspace. Visible but not an event. |

### 2.7 Log (auxiliary)

| Command | |
|---|---|
| `cmux log [--level] [--source] <message>` | Confirmed via `cmux --help` |
| `cmux list-log [--limit <n>]` | Confirmed via `cmux --help` |

Could be used for structured log-based completion detection, but events are cleaner.

### 2.8 Summary: what IS and is NOT available

| Capability | Available? |
|---|---|
| Send a completion notification programmatically | Yes — `cmux notify --title --body --surface` |
| Listen for notifications in a stream | Yes — `cmux events --category notification` |
| Listen for agent idle events (agent finished a turn) | Yes — `cmux events --category agent` (requires cmux-session.js plugin installed) |
| Listen for feed items (agent approvals/questions) | Yes — `cmux events --category feed` |
| Programmatic feed query (no TUI) | **No** — `cmux feed` is TUI-only |
| Named sync barrier between agent and orchestrator | Yes — `cmux wait-for` (tmux-compat) |
| Hook event → arbitrary command | Yes — `cmux set-hook` (UNVERIFIED event set) |

## 3. Proposed design: event-driven completion

### 3.1 Architecture overview

```
  ┌───────────────────────────┐       ┌──────────────────────────────────┐
  │  cmux agent (opencode)    │       │  cmux orchestrator (Claude/Code)  │
  │  in surface:172           │       │                                    │
  │                           │       │  1. agent-spawn.sh → surface:172  │
  │  ~/.config/opencode/      │       │  2. agent-send.sh (task spec)     │
  │    plugins/               │       │  3. poll-wait.sh surface:172 &    │
  │    cmux-session.js ───────┼──┐    │     feat/foo --timeout 1800       │
  │    cmux-feed.js ──────────┼──┤    │     (NEW, replaces poll-push as   │
  │                           │  │    │      primary wait)                │
  │  agent-notify.sh          │  │    │  4. On completion signal:         │
  │  (FINAL step)             │  │    │     - git fetch + check branch    │
  │    → cmux notify --title  │──┤    │     - verify.sh (hard gate)       │
  │      --body --surface     │  │    │     - pr-finish.sh                │
  │                           │  │    │  5. Fallback: poll-push.sh 30 600 │
  └───────────────────────────┘  │    │     (reduced timeout, secondary)  │
                                 │    └──────────────────────────────────┘
                                 │
                    ┌────────────┘
                    ▼
          ┌─────────────────────┐
          │  cmux event stream  │
          │                     │
          │  agent.hook.idle    │  ← cmux-session.js emits lifecycle
          │  notification.*     │  ← cmux notify emitted here
          │  feed.item.*        │  ← approvals / questions
          └──────────┬──────────┘
                     │
    cmux events --category agent --category notification --no-heartbeat
                     │
                     ▼
          ┌─────────────────────┐
          │  poll-wait.sh       │
          │  (NEW dual-source   │
          │   event listener)   │
          │                     │
          │  Sources checked    │
          │  in order:          │
          │  1. agent idle      │
          │     event           │
          │  2. CTB-DONE notify │
          │  3. git push poll   │
          │     (fallback)      │
          └─────────────────────┘
```

### 3.2 New script: `poll-wait.sh`

Replaces `poll-push.sh` as the primary wait. Consumes cmux events to detect agent completion, with `poll-push.sh` as the fallback.

```
Usage: poll-wait.sh --surface <ref> --branch <name> [--task <id>]
                    [--event-timeout <s>] [--total-timeout <s>]

  --surface <ref>        cmux surface ref (e.g. surface:172)
  --branch <name>        git branch to check on completion
  --task <id>            issue number (for notification matching)
  --event-timeout <s>    max wait for idle/notification event (default: 120s after event stream starts)
  --total-timeout <s>    overall timeout (default: 1800s, same as current poll-push.sh)
```

**Algorithm:**

1. **Start event listener** in background:
   ```bash
   cmux events --category agent --category notification --no-heartbeat \
     | grep -m1 -E "(lifecycle.*idle.*surface.*${SURF_NUM}|CTB-DONE.*task=${TASK})"
   ```
   The `grep -m1` exits on first match, closing the pipe → `cmux events` gets SIGPIPE → exits cleanly.

2. **Simultaneously start fallback poller** in background:
   ```bash
   poll-push.sh "$BRANCH" 30 "$TOTAL_TIMEOUT"
   ```

3. **Wait for either** to complete (using Bash `wait -n`), then kill the other.

4. **On event match (primary path):**
   - Extract completion info from the matched event line or from `cmux notify` payload.
   - Run `git fetch origin "$BRANCH" --quiet` to confirm push.
   - Report `COMPLETE surface=<ref> branch=<branch> method=event`.
   - Exit 0.

5. **On poll-push match (fallback path):**
   - `poll-push.sh` prints `PUSHED <sha>` or `TIMEOUT`.
   - Parse its output.
   - Report `COMPLETE surface=<ref> branch=<branch> method=poll`.
   - Exit 0 (or exit 1 on timeout).

### 3.3 Prerequisites (one-time setup)

```bash
yes | cmux hooks opencode install            # ~/.config/opencode/plugins/cmux-session.js
yes | cmux hooks opencode install --feed     # ~/.config/opencode/plugins/cmux-feed.js
```

These are idempotent. Must run BEFORE agent-spawn.sh for a surface to emit lifecycle events.

### 3.4 How the agent signals completion

Two complementary paths, both naturally covered by the event stream:

**Path A: Lifecycle idle (automatic)**
When the agent finishes processing a task and goes idle, the `cmux-session.js` plugin automatically emits an `agent.hook.*` event with `lifecycle: "idle"`. No action needed from the agent — it's automatic. The `poll-wait.sh` script detects this and proceeds.

**Path B: CTB-DONE notify (explicit)**
The agent's work prompt already instructs it to call `agent-notify.sh` as its final step. This sends a `cmux notify` which appears as a `notification.*` event in the stream. `poll-wait.sh` matches on `CTB-DONE` in the notification body.

Both paths fire → `poll-wait.sh` matches on whichever arrives first. Typically, the agent calls `agent-notify.sh`, then the session plugin emits idle shortly after.

### 3.5 Files to change

| File | Change | Why |
|---|---|---|
| `skills/cmux-agent-workflows/scripts/poll-wait.sh` | **NEW** | Event-driven wait replacing primary use of `poll-push.sh` |
| `skills/cmux-agent-workflows/scripts/agent-notify.sh` | **FIX** line 36: `cmux notify --title "CTB-DONE" --body "task=$TASK surface=$SURFACE status=$STATUS branch=${BRANCH:-}" --surface "$SURFACE"` | Currently passes CTB-DONE string as a bare positional arg (see §1.2 bug) |
| `skills/cmux-agent-workflows/SKILL.md` | Update delegation cycle (§Standard delegation cycle) and script table to use `poll-wait.sh` instead of `poll-push.sh` as primary; `poll-push.sh` becomes fallback-only | Documentation |
| `skills/cmux-agent-workflows/WAIT_WITHOUT_SLEEP.md` | Add reference to `poll-wait.sh` as the production wrapper around the `cmux events` pattern | Cross-reference |
| `docs/ORCHESTRATOR.md` | Update step 4 in cmux delegation cycle: "Poll" → "Wait (event-driven + poll fallback)" | Orchestrator rules |
| `docs/agent-notifications.md` | Update status from "IMPLEMENTED — agent-notify.sh + poll-push.sh fallback" to reflect event-driven consumption | Status doc |
| `tests/test_poll_wait.sh` | **NEW** | Tests for `poll-wait.sh` payload parsing and fallback logic |
| `tests/test_agent_notify.sh` | Update expected payload format for new `cmux notify --title/--body` flags | Align with fix |

**NOT changing:**
- `poll-push.sh` — remains as-is, used as fallback within `poll-wait.sh`
- `lib.sh`, `agent-spawn.sh`, `agent-send.sh`, `agent-kill.sh`, `verify.sh`, `pr-finish.sh` — no changes in L1 scope

### 3.6 Reduced `poll-push.sh` usage after migration

After migration, `poll-push.sh` is called ONLY as a fallback subprocess of `poll-wait.sh`. Its interval and timeout could be relaxed:
- Interval: 30 s → 60 s (fewer git ls-remote calls since it's now fallback)
- Timeout: 1800 s → 600 s (shorter because the primary event path should complete much faster)

## 4. Migration plan

### Step 1: Fix `agent-notify.sh` (safe, no behavioural change)
Fix the `cmux notify` call to use proper `--title`/`--body` flags. Existing tests still pass because `format_notify_payload` is unchanged; only the `cmux notify` invocation changes. This is cosmetic but necessary for the event stream to carry structured data.

### Step 2: Create `poll-wait.sh`
Write the dual-source waiter with event listener + poll fallback. Run unit tests on the event-parsing logic.

### Step 3: Integration test with live cmux
Start an agent, wait for idle event → verify `poll-wait.sh` detects it. Test both the idle path and the CTB-DONE notify path. Test the fallback path (poll-push.sh catches what events miss).

### Step 4: Update docs
Update SKILL.md, ORCHESTRATOR.md, WAIT_WITHOUT_SLEEP.md, agent-notifications.md.

### Step 5: Orchestrator adopts `poll-wait.sh`
The orchestrator (Claude) is instructed to use `poll-wait.sh` instead of `poll-push.sh` for the primary wait. The SKILL.md delegation cycle snippet reflects this.

### Step 6: Monitor & tune
After a few real delegation cycles, confirm:
- Which path fires most often (idle vs CTB-DONE)
- Whether the idle event arrives reliably or needs tuning
- Whether the fallback poll ever fires (if so, investigate why events were missed)

## 5. Open questions / risks

### 5.1 UNVERIFIED: Exact event names and payload shapes

The `WAIT_WITHOUT_SLEEP.md` document references `lifecycle: "idle"` in agent events, but the **exact** event name (e.g. `agent.hook.Stop`, `agent.hook.Idle`, `agent.hook.TurnComplete`) and JSON payload shape are UNVERIFIED. They depend on the version of `cmux-session.js` installed by `cmux hooks opencode install`.

**Mitigation:** Before implementing `poll-wait.sh`, capture a live trace:
```bash
cmux events --category agent --no-heartbeat \
  | jq -rc '{name, category, surface_id, payload}' \
  | head -20
```
Then hardcode the confirmed event name/payload path in `poll-wait.sh`.

### 5.2 UNVERIFIED: cmux events --category notification carries notify body

It is unconfirmed whether `cmux notify --body "..."` payloads appear verbatim in the `cmux events --category notification` stream, and under what JSON key. The `cmux events --help` example references `--name feed.item.received` but no notification event names are listed.

**Mitigation:** Same live trace as above, with `--category notification`. If notification bodies are NOT available in the event stream, drop Path B from `poll-wait.sh` and rely solely on the agent idle event (Path A) + poll fallback.

### 5.3 Opencode agent may NOT emit idle reliably

The `cmux-session.js` plugin emits lifecycle events, but the opencode agent may transition from `running` to `needsInput` (e.g. when it's waiting for approval) rather than `idle`. If the orchestrator doesn't respond to `needsInput`, the agent may hang and never reach `idle`.

**Mitigation:** Include `needsInput` as a completion-adjacent signal in `poll-wait.sh`. If an agent goes `needsInput`, the orchestrator should check whether it's stuck on an approval or waiting for a response. In headless mode (current default for opencode — no explicit `--yolo` flag observed), this is less likely.

### 5.4 Race condition: agent push + idle event ordering

The git push may complete BEFORE the idle event fires. The fallback poll will catch the push anyway, but the primary event path may fire on idle and then re-check git, finding the branch already there. This is harmless — the early-exit logic from commit 922c9ad in `poll-push.sh` already handles this case.

### 5.5 cmux events process lifecycle

When `grep -m1` exits after the first match, the pipe closes and `cmux events` receives SIGPIPE. This is the documented pattern in `WAIT_WITHOUT_SLEEP.md`. However, if the orchestrator restarts the event listener (e.g. after a disconnect), the `--after <seq>` or `--cursor-file` mechanism would be needed to avoid missing events that happened during the gap. For a single delegation cycle, this is fine because the listener starts before the agent is dispatched.

### 5.6 Biggest open risk: `cmux hooks` plugin installation is not part of the delegation cycle

The `agent-spawn.sh` script does NOT verify that `cmux hooks opencode install` has been run. If a new machine or fresh user runs delegation without installing hooks first, the agent sends NO lifecycle events, and `poll-wait.sh` would fall back to `poll-push.sh` every time — silently degrading to the current behaviour. This is acceptable as graceful degradation, but the orchestrator should emit a warning.

**Recommendation:** Add a one-line check in `agent-spawn.sh` (or in `poll-wait.sh`) that warns if `~/.config/opencode/plugins/cmux-session.js` is missing.

### 5.7 opencode agent has no native completion event

Unlike codex (which has `PreToolUse`/`PermissionRequest` hooks), opencode has no built-in completion signal. The `cmux-session.js` plugin provides lifecycle events, but these are cmux-injected, not native. If the plugin stops working after an opencode update (hook API change), the event stream goes silent.

**Mitigation:** `poll-push.sh` fallback ensures tasks never strand. The orchestrator should log when the fallback fires, to detect plugin breakage statistically.
