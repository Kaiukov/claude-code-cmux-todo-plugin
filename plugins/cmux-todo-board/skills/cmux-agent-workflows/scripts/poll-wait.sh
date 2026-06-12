#!/usr/bin/env bash
# Dual-source waiter: event-driven (cmux events) + poll fallback (poll-push.sh).
# Replaces poll-push.sh as the PRIMARY wait; poll-push.sh is the fallback.
#
# Usage: poll-wait.sh --surface <ref> --branch <name> [--task <id>]
#                     [--cwd <path>] [--event-timeout <s>] [--total-timeout <s>]
#
# How it works:
#   1. Start cmux events → ev.raw file in background; capture real PID (no leak).
#   2. Start a watchdog (sleep + kill) for the cmux events process.
#   3. Start poll-push.sh in background (sleeps 60s between polls).
#   4. Poll at 1s intervals, scanning ev.raw with event_line_matches() (respects
#      --cwd filter). First to finish wins.
#      - Event match: method=event.
#      - Poll push: poll.out has PUSHED → method=poll.
#   5. On total timeout: kill all, report TIMEOUT.
#
# Compatibility: macOS bash 3.2 (no `wait -n`, no `timeout`, no `read -t`).
# Uses a bash-native watchdog instead of GNU timeout.
#
# The event listener is intentionally enabled whenever `cmux` is available.
# The completion signal is the cmux notification stream. The idle lifecycle
# match remains a bonus for agents that emit it, but CTB-DONE must still wake
# the orchestrator even when no plugin files are present.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/lib.sh"

SURFACE=""; BRANCH=""; TASK=""; CWD=""; CWD_BASENAME=""; EVENT_TIMEOUT=120; TOTAL_TIMEOUT=1800
while [[ $# -gt 0 ]]; do
  case "$1" in
    --surface) SURFACE="$2"; shift 2 ;;
    --branch)  BRANCH="$2"; shift 2 ;;
    --task)    TASK="$2"; shift 2 ;;
    --event-timeout) EVENT_TIMEOUT="$2"; shift 2 ;;
    --total-timeout) TOTAL_TIMEOUT="$2"; shift 2 ;;
    --cwd)     CWD="$2"; CWD_BASENAME="$(basename "$2")"; shift 2 ;;
    --quiet)   LOG_LEVEL=quiet; shift ;;
    *) shift ;;
  esac
done

[[ -n "$SURFACE" && -n "$BRANCH" ]] || die "usage: poll-wait.sh --surface <ref> --branch <name> [--task <id>] [--cwd <path>] [--event-timeout <s>] [--total-timeout <s>]"

# ── event_line_matches: testable match function for the wait loop ──
# Returns 0 if the line matches the event pattern AND, when cwd_basename
# is given, also contains that basename as a fixed-string substring.
# This prevents cross-wake between parallel workers (#92).
event_line_matches() {
  local line="$1" pattern="$2" cwd_basename="${3:-}"
  # Must match the base event pattern (Stop / idle / CTB-DONE)
  if ! grep -qE "$pattern" <<<"$line"; then
    return 1
  fi
  # When a cwd filter is active, require the worktree basename in the line
  if [[ -n "$cwd_basename" ]]; then
    if ! grep -qF "$cwd_basename" <<<"$line"; then
      return 1
    fi
  fi
  return 0
}

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
# cmux events writes to ev.raw. The wait loop scans it with
# event_line_matches() so --cwd filtering is applied inline.
# The watchdog kills the REAL cmux events PID (no subshell leak).
if $EVENT_ENABLED; then
  # Write the cmux event stream to a temp file so we capture the REAL
  # cmux events PID — not a subshell wrapper.  The old subshell+pipe
  # approach leaked `cmux events` children because the EXIT trap only
  # killed the wrapper subshell, not the real listener process (#92).
  cmux events --category agent --category notification --no-heartbeat \
    > "$TMPDIR/ev.raw" 2>/dev/null &
  EVENT_PID=$!

  # Watchdog: kill the real cmux events process after EVENT_TIMEOUT.
  # If a match was already found in the wait loop, the kill is a no-op.
  (
    sleep "$EVENT_TIMEOUT"
    kill $EVENT_PID 2>/dev/null || true
  ) &
  WATCHDOG_PID=$!
fi

# ── background fallback poller (design §3.2 step 2) ──
"$DIR/poll-push.sh" "$BRANCH" 60 "$TOTAL_TIMEOUT" > "$TMPDIR/poll.out" 2>&1 &
POLL_PID=$!

# ── wait loop: scan ev.raw for matching event OR poller completion ──
# The event file is scanned each iteration with event_line_matches().
# If the watchdog kills cmux events, ev.raw stops growing; we fall through
# to the poll path naturally (no false-positive event matches).
ELAPSED=0
while (( ELAPSED < TOTAL_TIMEOUT )); do
  # Scan the event file for a matching line (respects --cwd filter)
  if $EVENT_ENABLED && [[ -f "$TMPDIR/ev.raw" ]]; then
    ev_matched=1
    while IFS= read -r line; do
      if event_line_matches "$line" "$EVENT_PATTERN" "${CWD_BASENAME:-}"; then
        ev_matched=0
        break
      fi
    done < "$TMPDIR/ev.raw"
    if [[ $ev_matched -eq 0 ]]; then
      kill $POLL_PID 2>/dev/null || true
      METHOD=event
      SUCCESS=0
      break
    fi
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
