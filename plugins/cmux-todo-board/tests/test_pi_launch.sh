#!/usr/bin/env bash
# Tests for Pi agent-kind launch path (#90).
# Verifies provider/model split, ready/kill patterns, trust pre-seed
# concepts, and regression-guards opencode/codex behavior.
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
# Test 4: agent_kind_supported pi → 0; opencode/codex still supported
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 4: agent_kind_supported ==="
for k in pi opencode codex; do
  if agent_kind_supported "$k"; then
    echo "  $k: supported (PASS)"
  else
    echo "  $k: NOT supported (FAIL)"
    failures=$((failures + 1))
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
# Test 6: opencode + codex launch_cmd UNCHANGED (regression guards)
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 6: opencode launch_cmd unchanged ==="
oc_cmd="$(agent_launch_cmd opencode "/tmp/wt" "deepseek/deepseek-v4-pro")"
expected_oc="cd '/tmp/wt' && opencode --model deepseek/deepseek-v4-pro"
if [[ "$oc_cmd" == "$expected_oc" ]]; then
  echo "  opencode: PASS"
else
  echo "  opencode: FAIL — got '$oc_cmd'"
  failures=$((failures + 1))
fi

echo "=== Test 7: codex launch_cmd unchanged ==="
cx_cmd="$(agent_launch_cmd codex "/tmp/wt" "gpt-5-codex")"
expected_cx="codex --cd '/tmp/wt' -m gpt-5-codex -a never -s danger-full-access"
if [[ "$cx_cmd" == "$expected_cx" ]]; then
  echo "  codex: PASS"
else
  echo "  codex: FAIL — got '$cx_cmd'"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Test 8: codex ready pattern unchanged
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 8: codex ready pattern unchanged ==="
cx_pattern="$(agent_ready_patterns codex)"
if [[ "$cx_pattern" == *"OpenAI Codex"* ]]; then
  echo "  codex pattern: PASS"
else
  echo "  codex pattern: FAIL — got '$cx_pattern'"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Test 9: pi kill pattern is precise (not bare 'pi')
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 9: pi kill pattern precision ==="
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
# Test 10: pi launch with extra args appended
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 10: pi launch with extra args ==="
cmd="$(agent_launch_cmd pi "/tmp/wt" "p/m" extra1 extra2)"
if [[ "$cmd" == *"extra1 extra2"* ]]; then
  echo "  extra args: PASS"
else
  echo "  extra args: FAIL — got '$cmd'"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Test 11: opencode ready pattern unchanged
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 11: opencode ready pattern unchanged ==="
oc_pattern="$(agent_ready_patterns opencode)"
if [[ "$oc_pattern" == *"anything"* && "$oc_pattern" == *"agents"* ]]; then
  echo "  opencode pattern: PASS"
else
  echo "  opencode pattern: FAIL — got '$oc_pattern'"
  failures=$((failures + 1))
fi

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All pi launch tests passed."
else
  echo "$failures test(s) failed."
  exit 1
fi
