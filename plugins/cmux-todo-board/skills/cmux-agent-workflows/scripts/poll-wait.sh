#!/usr/bin/env bash
# Dual-source waiter: event-driven (cmux events) + poll fallback (poll-push.sh).
# Replaces poll-push.sh as the PRIMARY wait; poll-push.sh is the fallback.
#
# Usage: poll-wait.sh --surface <ref> --branch <name> [--task <id>]
#                     [--event-timeout <s>] [--total-timeout <s>]
#
# How it works:
#   1. Start cmux events | grep in background (blocks on kernel events, no CPU).
#   2. Start a watchdog (sleep + kill) for the event listener.
#   3. Start poll-push.sh in background (sleeps 60s between polls).
#   4. Poll with kill -0 at 1s intervals. First to finish wins.
#      - Event match: grep writes to ev.result → method=event.
#      - Watchdog kill: no ev.result written → continue waiting for poll.
#      - Poll push: poll.out has PUSHED → method=poll.
#   5. On total timeout: kill all, report TIMEOUT.
#
# Compatibility: macOS bash 3.2 (no `wait -n`, no `timeout`, no `read -t`).
# Uses a bash-native watchdog instead of GNU timeout.
#
# The event listener is intentionally enabled whenever `cmux` is available.
# Codex hooks live in ~/.codex/hooks.json, while the completion signal itself
# is the cmux notification stream. The idle lifecycle match remains a bonus for
# agents that emit it, but CTB-DONE must still wake the orchestrator even when
# no opencode plugin files are present.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/lib.sh"

SURFACE=""; BRANCH=""; TASK=""; EVENT_TIMEOUT=120; TOTAL_TIMEOUT=1800
while [[ $# -gt 0 ]]; do
  case "$1" in
    --surface) SURFACE="$2"; shift 2 ;;
    --branch)  BRANCH="$2"; shift 2 ;;
    --task)    TASK="$2"; shift 2 ;;
    --event-timeout) EVENT_TIMEOUT="$2"; shift 2 ;;
    --total-timeout) TOTAL_TIMEOUT="$2"; shift 2 ;;
    --quiet) LOG_LEVEL=quiet; shift ;;
    *) shift ;;
  esac
done

[[ -n "$SURFACE" && -n "$BRANCH" ]] || die "usage: poll-wait.sh --surface <ref> --branch <name> [--task <id>] [--event-timeout <s>] [--total-timeout <s>]"

EVENT_PATTERN='(lifecycle.*idle|hook_event_name.*Stop|CTB-DONE.*task=)'
if [[ -n "$TASK" ]]; then
  EVENT_PATTERN="(lifecycle.*idle|hook_event_name.*Stop|CTB-DONE.*task=${TASK})"
fi
EVENT_PID=""; WATCHDOG_PID=""; POLL_PID=""
METHOD=""; SUCCESS=1
TMPDIR="$(mktemp -d)"
trap 'kill $EVENT_PID $WATCHDOG_PID $POLL_PID 2>/dev/null; rm -rf "$TMPDIR"' EXIT

# ── graceful degradation check (design §5.6) ──
EVENT_ENABLED=false
if command -v cmux &>/dev/null; then
  EVENT_ENABLED=true
else
  log "WARN: cmux not available → event path disabled, using poll fallback"
fi

# ── background event listener (design §3.2 step 1) ──
# Bash-native watchdog replaces GNU timeout. The event listener writes a result
# file on grep match; the watchdog only kills the process — NO result file means
# the listener was killed by timeout, so we fall through to the poll path.
if $EVENT_ENABLED; then
  # The event stream can carry either agent lifecycle idle or the explicit
  # CTB-DONE notification body. The latter is the Codex completion path.
  # NOTE: set +o pipefail inside the subshell prevents the upstream cmux
  # SIGPIPE (exit 141) from masking a successful grep match (exit 0).
  # Without this, set -euo pipefail at the script level would abort the
  # subshell before echo ever runs, making the event path silently dead.
  (
    set +o pipefail
    if cmux events --category agent --category notification --no-heartbeat 2>/dev/null \
         | grep -m1 -E "$EVENT_PATTERN" \
         > /dev/null 2>&1; then
      echo "event" > "$TMPDIR/ev.result"
    fi
  ) &
  EVENT_PID=$!

  # Watchdog: kill the event listener after EVENT_TIMEOUT seconds.
  # If grep already matched, the kill fails silently (process already dead).
  (
    sleep "$EVENT_TIMEOUT"
    kill $EVENT_PID 2>/dev/null || true
  ) &
  WATCHDOG_PID=$!
fi

# ── background fallback poller (design §3.2 step 2) ──
"$DIR/poll-push.sh" "$BRANCH" 60 "$TOTAL_TIMEOUT" > "$TMPDIR/poll.out" 2>&1 &
POLL_PID=$!

# ── wait loop: poll for the result file OR poller completion ──
# ev.result is written ONLY on a real grep match — never on watchdog timeout.
# This prevents the script from falsely reporting method=event when the event
# listener is killed by the watchdog (or when the event listener's command
# fails to start because cmux/other deps are missing).
ELAPSED=0
while (( ELAPSED < TOTAL_TIMEOUT )); do
  # Check if event listener produced a result (real grep match)
  if $EVENT_ENABLED && [[ -f "$TMPDIR/ev.result" ]]; then
    kill $POLL_PID 2>/dev/null || true
    METHOD=event
    SUCCESS=0
    break
  fi

  # Check if poller finished (push detected or poll timeout)
  if ! kill -0 $POLL_PID 2>/dev/null; then
    if grep -q "^PUSHED " "$TMPDIR/poll.out" 2>/dev/null; then
      $EVENT_ENABLED && kill $EVENT_PID 2>/dev/null || true
      METHOD=poll
      SUCCESS=0
      break
    fi
    # Poller exited without PUSHED (its own timeout). If events are disabled,
    # that's a hard fail. Otherwise, keep waiting for the event listener.
    if ! $EVENT_ENABLED; then
      SUCCESS=1
      break
    fi
    # Poller failed but event listener may still succeed — reset poll PID
    # so we don't keep checking it, and keep waiting.
    POLL_PID=""
  fi

  sleep 1
  ELAPSED=$((ELAPSED + 1))
done

# ── fell out of loop without a winner: total timeout ──
if [[ -z "$METHOD" ]]; then
  $EVENT_ENABLED && kill $EVENT_PID 2>/dev/null || true
  kill $POLL_PID 2>/dev/null || true
  # Last-resort check: poll may have finished between iterations
  if grep -q "^PUSHED " "$TMPDIR/poll.out" 2>/dev/null; then
    METHOD=poll
    SUCCESS=0
  fi
fi

# ── output ──
if [[ $SUCCESS -eq 0 ]]; then
  echo "COMPLETE surface=$SURFACE branch=$BRANCH method=${METHOD:-poll}"
  exit 0
else
  echo "TIMEOUT surface=$SURFACE branch=$BRANCH after ${TOTAL_TIMEOUT}s"
  exit 1
fi
