#!/usr/bin/env bash
# Tests for Pi agent-kind launch path (#90).
# Verifies provider/model split, ready/kill patterns, and trust pre-seed
# concepts. Regression-asserts AGENT_KINDS is pi-only (#98).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_FILE="$REPO_ROOT/skills/cmux-agent-workflows/scripts/lib.sh"
FIXTURE="$SCRIPT_DIR/fixtures/pi-ready-footer.txt"

if [[ ! -f "$LIB_FILE" ]]; then
  echo "FAIL: lib.sh not found at $LIB_FILE"
  exit 1
fi
if [[ ! -f "$FIXTURE" ]]; then
  echo "FAIL: fixture not found at $FIXTURE"
  exit 1
fi

source "$LIB_FILE"

failures=0

# Normalize helper matching wait_agent_ready logic for pi (same as opencode:
# strip ALL whitespace + box-drawing chars).
normalize_pi_screen() {
  printf '%s' "$1" | tr -d '[:space:]┃┏┓┗┛━╹▀│─┌┐└┘●'
}

# ══════════════════════════════════════════════════════════════════════
# Test 1: agent_launch_cmd pi — happy path
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 1: agent_launch_cmd pi happy path ==="
cmd="$(agent_launch_cmd pi "/tmp/test-wt" "opencode-go/deepseek-v4-pro")"
expected="cd '/tmp/test-wt' && pi --provider opencode-go --model deepseek-v4-pro"
if [[ "$cmd" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: expected '$expected', got '$cmd'"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Test 2: provider/model split on FIRST / only
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 2: split on FIRST / only ==="
cmd="$(agent_launch_cmd pi "/tmp/wt" "a/b/c")"
expected="cd '/tmp/wt' && pi --provider a --model b/c"
if [[ "$cmd" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: expected '$expected', got '$cmd'"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Test 3: bareword (no /) — die, non-zero exit
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 3: bareword (no slash) rejects ==="
if (agent_launch_cmd pi "/tmp/wt" "bareword") 2>/dev/null; then
  echo "FAIL: bareword should fail"
  failures=$((failures + 1))
else
  echo "PASS"
fi

# ══════════════════════════════════════════════════════════════════════
# Test 4: agent_kind_supported pi → 0; non-pi kinds rejected
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 4: agent_kind_supported ==="
if agent_kind_supported "pi"; then
  echo "  pi: supported (PASS)"
else
  echo "  pi: NOT supported (FAIL)"
  failures=$((failures + 1))
fi
# Non-pi kinds must NOT be supported
for k in opencode codex; do
  if agent_kind_supported "$k"; then
    echo "  $k: supported (FAIL — should be rejected)"
    failures=$((failures + 1))
  else
    echo "  $k: correctly rejected (PASS)"
  fi
done

# ══════════════════════════════════════════════════════════════════════
# Test 5: pi ready pattern matches real fixture; rejects bare shell line
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 5: pi ready pattern ==="
fixture="$(cat "$FIXTURE")"
normalized="$(normalize_pi_screen "$fixture")"
pi_pattern="$(agent_ready_patterns pi)"

if grep -qE "$pi_pattern" <<<"$normalized"; then
  echo "  fixture match: PASS"
else
  echo "  fixture match: FAIL"
  failures=$((failures + 1))
fi

# Bare shell line should NOT match
bare_line='user@host ~ % '
bare_norm="$(normalize_pi_screen "$bare_line")"
if grep -qE "$pi_pattern" <<<"$bare_norm"; then
  echo "  bare line false-positive: FAIL"
  failures=$((failures + 1))
else
  echo "  bare line reject: PASS"
fi

# ══════════════════════════════════════════════════════════════════════
# Test 6: non-pi kind → agent_launch_cmd errors (regression #98)
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 6: non-pi launch_cmd errors ==="
for k in opencode codex; do
  if (agent_launch_cmd "$k" "/tmp/wt" "p/model" 2>/dev/null); then
    echo "  $k launch_cmd: FAIL (should error)"
    failures=$((failures + 1))
  else
    echo "  $k launch_cmd: correctly failed (PASS)"
  fi
done

# ══════════════════════════════════════════════════════════════════════
# Test 7: AGENT_KINDS contains exactly pi
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 7: AGENT_KINDS=(pi) ==="
if [[ "${AGENT_KINDS[*]}" == "pi" && "${#AGENT_KINDS[@]}" == "1" ]]; then
  echo "PASS: AGENT_KINDS=(pi)"
else
  echo "FAIL: AGENT_KINDS=(${AGENT_KINDS[*]})  (len=${#AGENT_KINDS[@]})"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Test 8: pi kill pattern is precise (not bare 'pi')
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 8: pi kill pattern precision ==="
pi_kill="$(agent_kill_pattern pi)"
if [[ "$pi_kill" == "pi --provider|pi --model" ]]; then
  echo "  kill pattern: PASS"
else
  echo "  kill pattern: FAIL — got '$pi_kill'"
  failures=$((failures + 1))
fi
# Must NOT match a bare 'pi' word alone
if echo "pip install something" | grep -qE "$pi_kill" 2>/dev/null; then
  echo "  false match on 'pip': FAIL"
  failures=$((failures + 1))
else
  echo "  no false match on 'pip': PASS"
fi

# ══════════════════════════════════════════════════════════════════════
# Test 9: pi launch with extra args appended
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 9: pi launch with extra args ==="
cmd="$(agent_launch_cmd pi "/tmp/wt" "p/m" extra1 extra2)"
if [[ "$cmd" == *"extra1 extra2"* ]]; then
  echo "  extra args: PASS"
else
  echo "  extra args: FAIL — got '$cmd'"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Test 10: repo grep — no surviving binary launch invocations (#98)
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 10: no legacy binary launchers in scripts ==="
SCRIPTS_DIR="$REPO_ROOT/skills/cmux-agent-workflows/scripts"
if grep -rnE "opencode --model|codex --cd" "$SCRIPTS_DIR" 2>/dev/null; then
  echo "FAIL: legacy binary launch invocation found in scripts"
  failures=$((failures + 1))
else
  echo "PASS: no legacy binary launchers in scripts"
fi

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All pi launch tests passed."
else
  echo "$failures test(s) failed."
  exit 1
fi
