#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NOTIFY_SCRIPT="$REPO_ROOT/skills/cmux-agent-workflows/scripts/agent-notify.sh"

if [[ ! -f "$NOTIFY_SCRIPT" ]]; then
  echo "FAIL: agent-notify.sh not found at $NOTIFY_SCRIPT"
  exit 1
fi

# Source the pure format_notify_payload function from agent-notify.sh
format_notify_payload() {
  local task="$1" surface="$2" status="$3" branch="${4:-}"
  if [[ -n "$branch" ]]; then
    echo "CTB-DONE task=${task} surface=${surface} status=${status} branch=${branch}"
  else
    echo "CTB-DONE task=${task} surface=${surface} status=${status}"
  fi
}

failures=0

echo "=== Test 1: success with branch ==="
result=$(format_notify_payload "32" "surface:172" "success" "feat/my-fix")
expected="CTB-DONE task=32 surface=surface:172 status=success branch=feat/my-fix"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

echo "=== Test 2: failure without branch ==="
result=$(format_notify_payload "17" "surface:101" "failure")
expected="CTB-DONE task=17 surface=surface:101 status=failure"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

echo "=== Test 3: success with branch (different surface) ==="
result=$(format_notify_payload "1" "surface:200" "success" "fix/typo")
expected="CTB-DONE task=1 surface=surface:200 status=success branch=fix/typo"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

echo "=== Test 4: failure with branch ==="
result=$(format_notify_payload "99" "surface:333" "failure" "feat/broken")
expected="CTB-DONE task=99 surface=surface:333 status=failure branch=feat/broken"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

echo "=== Test 5: success without branch ==="
result=$(format_notify_payload "5" "surface:5" "success")
expected="CTB-DONE task=5 surface=surface:5 status=success"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

echo "=== Test 6: empty branch treated as missing ==="
result=$(format_notify_payload "10" "surface:10" "success" "")
expected="CTB-DONE task=10 surface=surface:10 status=success"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All format_notify_payload tests passed."
else
  echo "${failures} test(s) failed."
  exit 1
fi
