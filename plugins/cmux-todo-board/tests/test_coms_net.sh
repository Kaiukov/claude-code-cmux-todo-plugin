#!/usr/bin/env bash
# Tests for coms-net event bus — bash-only (macOS 3.2 compatible).
# CI is bash-only (no Bun/node guaranteed) — test DATA + wiring + helper contract.
#
# Tests:
#   1. All 4 deliverable files exist and are non-empty.
#   2. Server references auth-token, TTL, and channel isolation.
#   3. Extension emits a done/completion event.
#   4. Helper is executable, bash -n clean, exits non-zero when bus unreachable.
#   5. Smoke test: if bun exists, start hub, POST done, await, assert received.
#
# Prints PASS/FAIL (or SKIP) per case, exits 1 on any real failure.
set -euo pipefail

# ── Paths ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

SERVER_TS="$REPO_ROOT/scripts/coms-net-server.ts"
EXTENSION_TS="$REPO_ROOT/.pi/extensions/coms-net.ts"
AWAIT_SH="$REPO_ROOT/plugins/cmux-todo-board/skills/cmux-agent-workflows/scripts/coms-net-await.sh"
DESIGN_MD="$REPO_ROOT/docs/coms-net-design.md"

PASS=0
FAIL=0
SKIP=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP + 1)); }

# ── Test 1: Files exist and are non-empty ────────────────────────────────
echo "=== Test 1: Deliverable files exist and are non-empty ==="

for f in "$SERVER_TS" "$EXTENSION_TS" "$AWAIT_SH" "$DESIGN_MD"; do
  fn="$(basename "$f")"
  if [[ -f "$f" ]]; then
    if [[ -s "$f" ]]; then
      pass "$fn exists and is non-empty"
    else
      fail "$fn exists but is EMPTY"
    fi
  else
    fail "$fn does NOT exist at $f"
  fi
done

# ── Test 2: Server references key concepts ───────────────────────────────
echo ""
echo "=== Test 2: coms-net-server.ts references auth-token, TTL, channel isolation ==="

check_ref() {
  local file="$1" label="$2" pattern="$3"
  if grep -q "$pattern" "$file"; then
    pass "$label referenced in $(basename "$file")"
  else
    fail "$label NOT referenced in $(basename "$file")"
  fi
}

check_ref "$SERVER_TS" "auth-token" "auth-token\|authorization\|Bearer"
check_ref "$SERVER_TS" "TTL" "TTL\|ttlSec\|COMS_NET_TTL_SEC\|sweepExpired"
check_ref "$SERVER_TS" "channel isolation" "channel\|parseChannel"

# ── Test 3: Extension emits done/completion event ────────────────────────
echo ""
echo "=== Test 3: coms-net.ts emits a done/completion event ==="

check_ref "$EXTENSION_TS" "done event" 'type.*done\|"done"'
check_ref "$EXTENSION_TS" "agent_end hook" "agent_end"
check_ref "$EXTENSION_TS" "postEvent" "postEvent\|fetch.*send"
check_ref "$EXTENSION_TS" "COMS_NET_TOKEN" "COMS_NET_TOKEN"
check_ref "$EXTENSION_TS" "channel isolation" "channel\|COMS_NET_CHANNEL"

# ── Test 4: Helper script checks ────────────────────────────────────────
echo ""
echo "=== Test 4: coms-net-await.sh executable, bash -n clean, exits non-zero when bus unreachable ==="

if [[ -x "$AWAIT_SH" ]]; then
  pass "coms-net-await.sh is executable"
else
  fail "coms-net-await.sh is NOT executable"
fi

if bash -n "$AWAIT_SH" 2>&1; then
  pass "coms-net-await.sh passes bash -n (syntax check)"
else
  fail "coms-net-await.sh FAILS bash -n"
fi

# Test: exits non-zero when hub is unreachable (connect to a closed port with short timeout)
echo "  (testing unreachable-hub exit code...)"
if output=$(COMS_NET_TOKEN="test-token" \
  bash "$AWAIT_SH" \
    --channel "test-channel" \
    --timeout 1 \
    --hub "http://127.0.0.1:19999" 2>&1); then
  fail "coms-net-await.sh exited 0 when hub is unreachable (should exit non-zero)"
else
  rc=$?
  if [[ $rc -ne 0 ]]; then
    pass "coms-net-await.sh exits non-zero ($rc) when hub is unreachable (fallback path proven)"
  else
    fail "coms-net-await.sh exited 0 on unreachable hub"
  fi
fi

# Test: exits non-zero when COMS_NET_TOKEN is not set
echo "  (testing missing-token exit code...)"
if output=$(COMS_NET_TOKEN="" \
  bash "$AWAIT_SH" \
    --channel "test" \
    --timeout 1 2>&1); then
  fail "coms-net-await.sh exited 0 when COMS_NET_TOKEN is empty"
else
  rc=$?
  if [[ $rc -ne 0 ]]; then
    pass "coms-net-await.sh exits non-zero ($rc) when COMS_NET_TOKEN is empty"
  else
    fail "coms-net-await.sh exited 0 when COMS_NET_TOKEN is empty"
  fi
fi

# ── Test 5: Bun smoke test (if available) ────────────────────────────────
echo ""
echo "=== Test 5: Smoke test (bun integration) ==="

if command -v bun &>/dev/null; then
  echo "  (bun is available — running smoke test)"

  # Pick an ephemeral port
  HUB_PORT=19998
  # Make sure port is free
  if lsof -i ":$HUB_PORT" &>/dev/null 2>&1; then
    echo "  (port $HUB_PORT in use, trying another)"
    HUB_PORT=19997
  fi

  TOKEN="smoke-test-token-$$"
  CHANNEL="smoke-test-channel-$$"

  # Start hub in background
  COMS_NET_TOKEN="$TOKEN" \
  COMS_NET_PORT="$HUB_PORT" \
  COMS_NET_HOST="127.0.0.1" \
    bun run "$SERVER_TS" &
  HUB_PID=$!

  # Wait for hub to be ready
  HUB_URL="http://127.0.0.1:${HUB_PORT}"
  for i in $(seq 1 20); do
    if curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer ${TOKEN}" \
      "$HUB_URL/health" 2>/dev/null | grep -q "200"; then
      break
    fi
    if [[ $i -eq 20 ]]; then
      fail "Hub failed to start within 10s"
      kill $HUB_PID 2>/dev/null || true
      break
    fi
    sleep 0.5
  done

  # Check if hub started successfully
  if kill -0 $HUB_PID 2>/dev/null; then
    pass "Hub started successfully on port $HUB_PORT"

    # POST a done event
    echo "  (POSTing done event...)"
    SEND_RESP=$(curl -s -f \
      -X POST \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"type\":\"done\",\"channel\":\"${CHANNEL}\",\"branch\":\"test-branch\",\"status\":\"success\",\"ts\":$(date +%s)000}" \
      "$HUB_URL/send?channel=${CHANNEL}" 2>&1) || true

    if echo "$SEND_RESP" | grep -q '"ok"'; then
      pass "POST /send returned ok"

      # Await the event using the helper script
      echo "  (awaiting event via helper script...)"
      AWAIT_OUT=$(COMS_NET_TOKEN="$TOKEN" \
        bash "$AWAIT_SH" \
          --channel "$CHANNEL" \
          --timeout 10 \
          --hub "$HUB_URL" 2>&1) || true

      if echo "$AWAIT_OUT" | grep -q '"done"'; then
        pass "coms-net-await.sh received the done event"

        # Verify the event shape
        if echo "$AWAIT_OUT" | grep -q '"type"' && \
           echo "$AWAIT_OUT" | grep -q '"channel"' && \
           echo "$AWAIT_OUT" | grep -q '"status"'; then
          pass "Done event has required fields (type, channel, status)"
        else
          fail "Done event missing required fields"
        fi
      else
        fail "coms-net-await.sh did NOT receive the done event (output: $AWAIT_OUT)"
      fi
    else
      fail "POST /send failed (response: $SEND_RESP)"
    fi

    # Test channel isolation: await on a different channel should timeout
    echo "  (testing channel isolation...)"
    ISO_RC=0
    set +e
    ISO_OUT=$(COMS_NET_TOKEN="$TOKEN" \
      bash "$AWAIT_SH" \
        --channel "other-channel-$$" \
        --timeout 3 \
        --hub "$HUB_URL" 2>&1)
    ISO_RC=$?
    set -e

    if [[ $ISO_RC -ne 0 ]]; then
      pass "Channel isolation: await on different channel timed out as expected"
    else
      fail "Channel isolation: await on different channel should have timed out (got: $ISO_OUT)"
    fi

    # Stop hub
    kill $HUB_PID 2>/dev/null || true
    wait $HUB_PID 2>/dev/null || true
  fi
else
  skip "bun not available — skipping integration smoke test"
  echo "  (install bun: curl -fsSL https://bun.sh/install | bash)"
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  Results: $PASS PASS, $FAIL FAIL, $SKIP SKIP"
echo "========================================"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
