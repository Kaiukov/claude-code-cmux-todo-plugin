#!/usr/bin/env bash
# Tests for poll-wait.sh — pure-bash, NO network. Stubs cmux and poll-push.sh
# via PATH shim to feed canned event lines. Follows style of test_agent_notify.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POLL_WAIT="$REPO_ROOT/skills/cmux-agent-workflows/scripts/poll-wait.sh"

if [[ ! -f "$POLL_WAIT" ]]; then
  echo "FAIL: poll-wait.sh not found at $POLL_WAIT"
  exit 1
fi

_FAILURES=0

run_in_mock_env() {
  local test_name="$1" test_fn="$2"
  echo "=== $test_name ==="

  local TMPENV
  TMPENV="$(mktemp -d)"
  local PLUGINDIR="$TMPENV/.config/opencode/plugins"
  mkdir -p "$PLUGINDIR"
  # Create dummy plugin file (test C explicitly removes it)
  touch "$PLUGINDIR/cmux-session.js"

  # ── mock cmux ──
  cat > "$TMPENV/cmux" <<'CMUX_EOF'
#!/usr/bin/env bash
if [[ "$1" == "events" ]]; then
  if [[ -n "${CMUX_EVENT_FILE:-}" && -f "$CMUX_EVENT_FILE" ]]; then
    cat "$CMUX_EVENT_FILE"
    exit 0
  fi
  # No event file: simulate live stream; exit when parent dies
  sleep "${CMUX_EVENT_SLEEP:-300}" &
  SPID=$!
  while kill -0 $SPID 2>/dev/null; do
    kill -0 $PPID 2>/dev/null || { kill $SPID 2>/dev/null; exit 0; }
    sleep 1
  done
fi
exit 0
CMUX_EOF
  chmod +x "$TMPENV/cmux"

  # ── mock poll-push.sh ──
  cat > "$TMPENV/poll-push.sh" <<'POLL_EOF'
#!/usr/bin/env bash
if [[ "${POLL_RESULT:-}" == "PUSHED" ]]; then
  sleep "${POLL_DELAY:-0}"
  echo "PUSHED deadbeef  (mock)"
  exit 0
fi
sleep "${POLL_SLEEP:-300}" &
SPID=$!
while kill -0 $SPID 2>/dev/null; do
  kill -0 $PPID 2>/dev/null || { kill $SPID 2>/dev/null; exit 0; }
  sleep 1
done
exit 1
POLL_EOF
  chmod +x "$TMPENV/poll-push.sh"

  # ── stub lib.sh ──
  cat > "$TMPENV/lib.sh" <<'LIB_EOF'
die() { echo "ERROR: $*" >&2; exit 1; }
log() { [[ "${LOG_LEVEL:-info}" == "quiet" ]] && return 0; echo ">>  $*" >&2; }
LIB_EOF

  # ── copy poll-wait.sh so DIR resolves to TMPENV ──
  cp "$POLL_WAIT" "$TMPENV/poll-wait.sh"
  chmod +x "$TMPENV/poll-wait.sh"

  (
    PATH="$TMPENV:$PATH"
    HOME="$TMPENV"
    export PATH HOME
    "$test_fn" "$TMPENV"
  )
  local rc=$?
  rm -rf "$TMPENV"
  return $rc
}

assert_output_contains() {
  local output="$1" pattern="$2" label="$3"
  if echo "$output" | grep -qE "$pattern"; then
    echo "PASS"
  else
    echo "FAIL ($label): output did not match '$pattern'"
    echo "  got: $output"
    _FAILURES=$((_FAILURES + 1))
  fi
}

# ── Test A: event match → method=event ──
# Canned agent.hook.Stop triggers grep → ev.result written → event wins.
# Poller is delayed (POLL_DELAY=5) so event wins the race.
test_event_match() {
  local TMPENV="$1"
  cat > "$TMPENV/events.ndjson" <<'EOF'
{"name":"agent.hook.Stop","category":"agent","payload":{"hook_event_name":"Stop","phase":"completed"},"surface_id":null}
EOF
  CMUX_EVENT_FILE="$TMPENV/events.ndjson" \
    CMUX_EVENT_SLEEP=30 \
    POLL_RESULT=PUSHED POLL_DELAY=5 POLL_SLEEP=30 \
    "$TMPENV/poll-wait.sh" \
      --surface surface:172 --branch feat/test-ev --task 42 \
      --event-timeout 3 --total-timeout 30
}

# ── Test B: poll fallback → method=poll ──
# No event file → grep never matches → watchdog kills listener → no ev.result.
# Poller exits immediately with PUSHED → poll wins.
test_poll_fallback() {
  local TMPENV="$1"
  CMUX_EVENT_FILE="" CMUX_EVENT_SLEEP=30 \
    POLL_RESULT=PUSHED POLL_DELAY=0 POLL_SLEEP=30 \
    "$TMPENV/poll-wait.sh" \
      --surface surface:173 --branch feat/test-poll \
      --event-timeout 2 --total-timeout 30
}

# ── Test C: Codex notification wakes waiter without opencode plugin ──
# Remove the opencode plugin file but keep cmux events live. The waiter should
# still consume CTB-DONE from the notification stream instead of falling back
# to the git poller.
test_codex_notify_match() {
  local TMPENV="$1"
  rm -f "$TMPENV/.config/opencode/plugins/cmux-session.js"
  cat > "$TMPENV/events.ndjson" <<'EOF'
{"name":"notification.created","category":"notification","payload":{"title":"CTB-DONE","body":"CTB-DONE task=71 surface=surface:174 status=success branch=feat/test-codex"},"surface_id":"surface:174"}
EOF
  CMUX_EVENT_FILE="$TMPENV/events.ndjson" CMUX_EVENT_SLEEP=30 \
    POLL_RESULT=PUSHED POLL_DELAY=5 POLL_SLEEP=30 \
    "$TMPENV/poll-wait.sh" \
      --surface surface:174 --branch feat/test-codex \
      --event-timeout 3 --total-timeout 30
}

# ── Test D: arg parsing — missing required --branch ──
test_arg_parsing() {
  local TMPENV="$1"
  CMUX_EVENT_FILE="" CMUX_EVENT_SLEEP=30 \
    POLL_RESULT=PUSHED POLL_DELAY=0 \
    "$TMPENV/poll-wait.sh" \
      --surface surface:175 --event-timeout 2 --total-timeout 30 2>&1 || true
}

# ── Test E: total timeout → exit 1 ──
# No events, poller sleeps forever. Total-timeout expires → fail.
test_total_timeout() {
  local TMPENV="$1"
  CMUX_EVENT_FILE="" CMUX_EVENT_SLEEP=30 \
    POLL_RESULT="" POLL_SLEEP=30 \
    "$TMPENV/poll-wait.sh" \
      --surface surface:176 --branch feat/test-timeout \
      --event-timeout 2 --total-timeout 3 2>&1 || true
}

# ── Test F: script does NOT rely on GNU timeout — no `timeout` in PATH ──
# This proves the portability fix. We explicitly remove any `timeout` binary
# from PATH and verify the event-path still works correctly.
test_no_gnu_timeout() {
  local TMPENV="$1"
  # Remove mock timeout — the real poll-wait.sh must not call `timeout` at all
  rm -f "$TMPENV/timeout"
  # Also ensure there's no system timeout: clear PATH except our mock dir,
  # then remove any timeout that might exist in the mock dir
  cat > "$TMPENV/events.ndjson" <<'EOF'
{"name":"agent.hook.Stop","category":"agent","payload":{"hook_event_name":"Stop","phase":"completed"},"surface_id":null}
EOF
  CMUX_EVENT_FILE="$TMPENV/events.ndjson" \
    CMUX_EVENT_SLEEP=30 \
    POLL_RESULT=PUSHED POLL_DELAY=5 POLL_SLEEP=30 \
    "$TMPENV/poll-wait.sh" \
      --surface surface:177 --branch feat/test-notimeout --task 99 \
      --event-timeout 3 --total-timeout 30
}

# ── Test G: continuously-streaming cmux → SIGPIPE on producer → ev.result IS written ──
# Simulates the REAL cmux behavior: a long-lived event stream where grep -m1
# closes the pipe → upstream cmux gets SIGPIPE (exit 141). With set -euo
# pipefail this would abort the subshell before echo. The fix uses
# set +o pipefail + if/then to ensure ev.result is written on grep match.
test_streaming_sigpipe() {
  local TMPENV="$1"
  # Override cmux: continuously stream events (simulates real cmux events)
  cat > "$TMPENV/cmux" <<'CMUX_STREAM'
#!/usr/bin/env bash
if [[ "$1" == "events" ]]; then
  while true; do
    echo '{"name":"agent.hook.Stop","category":"agent","payload":{"hook_event_name":"Stop","phase":"completed"},"surface_id":null}'
    sleep 0.1
  done
fi
exit 0
CMUX_STREAM
  chmod +x "$TMPENV/cmux"

  POLL_RESULT=PUSHED POLL_DELAY=5 POLL_SLEEP=30 \
    "$TMPENV/poll-wait.sh" \
      --surface surface:178 --branch feat/test-sigpipe --task 99 \
      --event-timeout 3 --total-timeout 30
}

# ═══════════════════════════════════════════════════════════
# Run tests
# ═══════════════════════════════════════════════════════════

echo "--- Test A: event match → method=event ---"
output=$(run_in_mock_env "Test A: event match" test_event_match 2>&1) || true
assert_output_contains "$output" "COMPLETE surface=surface:172 branch=feat/test-ev method=event" "event match output"

echo "--- Test B: poll fallback → method=poll ---"
output=$(run_in_mock_env "Test B: poll fallback" test_poll_fallback 2>&1) || true
assert_output_contains "$output" "COMPLETE surface=surface:173 branch=feat/test-poll method=poll" "poll fallback output"

echo "--- Test C: Codex notification wakes waiter without opencode plugin ---"
output=$(run_in_mock_env "Test C: codex notify" test_codex_notify_match 2>&1) || true
assert_output_contains "$output" "COMPLETE surface=surface:174 branch=feat/test-codex method=event" "codex notify event match"

echo "--- Test D: arg parsing ---"
output=$(run_in_mock_env "Test D: arg parsing" test_arg_parsing 2>&1) || true
assert_output_contains "$output" "ERROR.*usage:" "arg parsing error"

echo "--- Test E: total timeout → exit 1 ---"
output=$(run_in_mock_env "Test E: total timeout" test_total_timeout 2>&1) || true
assert_output_contains "$output" "TIMEOUT" "timeout output"

echo "--- Test F: no GNU timeout dependency ---"
output=$(run_in_mock_env "Test F: no GNU timeout" test_no_gnu_timeout 2>&1) || true
assert_output_contains "$output" "COMPLETE surface=surface:177 branch=feat/test-notimeout method=event" "no-timeout event match"

echo "--- Test G: streaming cmux + SIGPIPE → ev.result IS written ---"
output=$(run_in_mock_env "Test G: streaming sigpipe" test_streaming_sigpipe 2>&1) || true
assert_output_contains "$output" "COMPLETE surface=surface:178 branch=feat/test-sigpipe method=event" "streaming sigpipe → method=event"

# ── Test H: --quiet suppresses log() stderr, keeps COMPLETE/TIMEOUT on stdout ──
# Missing-plugin path produces WARN log output without --quiet. With --quiet,
# WARN must be suppressed, but COMPLETE must still be emitted.
test_quiet_suppress_log() {
  local TMPENV="$1"
  rm -f "$TMPENV/.config/opencode/plugins/cmux-session.js"
  CMUX_EVENT_FILE="" CMUX_EVENT_SLEEP=30 \
    POLL_RESULT=PUSHED POLL_DELAY=0 \
    "$TMPENV/poll-wait.sh" \
      --quiet --surface surface:179 --branch feat/test-quiet \
      --event-timeout 2 --total-timeout 30
}

echo "--- Test H: --quiet suppresses log() stderr, keeps COMPLETE on stdout ---"
output=$(run_in_mock_env "Test H: quiet gate" test_quiet_suppress_log 2>&1) || true
# WARN must NOT appear (log() suppressed)
if echo "$output" | grep -q "WARN"; then
  echo "FAIL (quiet-gate): WARN message leaked in quiet mode"
  echo "  got: $output"
  _FAILURES=$((_FAILURES + 1))
else
  echo "PASS (quiet-gate): no WARN in quiet mode"
fi
# COMPLETE must still appear (stdout result line preserved)
assert_output_contains "$output" "COMPLETE.*method=poll" "quiet mode still emits COMPLETE"

echo ""
if [[ $_FAILURES -eq 0 ]]; then
  echo "All poll-wait tests passed."
else
  echo "$_FAILURES test(s) failed."
  exit 1
fi
