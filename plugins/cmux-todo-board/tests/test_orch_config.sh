#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCH_CONFIG="$REPO_ROOT/bin/orch-config"

if [[ ! -f "$ORCH_CONFIG" ]]; then
  echo "FAIL: orch-config not found at $ORCH_CONFIG"
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"

failures=0

assert_json_field() {
  local json="$1"
  local field="$2"
  local expected="$3"
  local actual
  actual="$(echo "$json" | jq -r ".${field}")"
  if [[ "$actual" == "$expected" ]]; then
    echo "PASS"
  else
    echo "FAIL: ${field}='$actual' expected '$expected'"
    failures=$((failures + 1))
  fi
}

echo "=== Test 1: --list-profiles is deterministic ==="
list_out="$($ORCH_CONFIG --list-profiles)"
expected_list=$'repo-scout\nbackend\nreviewer'
if [[ "$list_out" == "$expected_list" ]]; then
  echo "PASS"
else
  echo "FAIL: got:\n$list_out"
  failures=$((failures + 1))
fi

echo "=== Test 2: repo-scout profile lookup works ==="
json="$($ORCH_CONFIG --get-profile repo-scout)"
assert_json_field "$json" role "repo-scout"
assert_json_field "$json" runtime "pi"
assert_json_field "$json" model "deepseek-v4-flash"
assert_json_field "$json" permissions "read-only"
assert_json_field "$json" launch_mode "via-pi"

echo "=== Test 3: backend profile lookup works ==="
json="$($ORCH_CONFIG --get-profile backend)"
assert_json_field "$json" role "backend"
assert_json_field "$json" runtime "pi"
assert_json_field "$json" model "deepseek-v4-pro"
assert_json_field "$json" permissions "write"
assert_json_field "$json" launch_mode "via-pi"

echo "=== Test 4: reviewer profile lookup works ==="
json="$($ORCH_CONFIG --get-profile reviewer)"
assert_json_field "$json" role "reviewer"
assert_json_field "$json" runtime "pi"
assert_json_field "$json" model "deepseek-v4-pro"
assert_json_field "$json" permissions "read-only"
assert_json_field "$json" launch_mode "via-pi"

echo "=== Test 5: output includes required fields ==="
keys_ok="$(echo "$json" | jq -r 'has("role") and has("runtime") and has("model") and has("permissions") and has("launch_mode")')"
if [[ "$keys_ok" == "true" ]]; then
  echo "PASS"
else
  echo "FAIL: required fields missing"
  failures=$((failures + 1))
fi

echo "=== Test 6: unknown profile fails ==="
if "$ORCH_CONFIG" --get-profile unknown >/dev/null 2>&1; then
  echo "FAIL: expected failure for unknown profile"
  failures=$((failures + 1))
else
  echo "PASS"
fi

echo "=== Test 7: list-profiles rejects extra args ==="
if "$ORCH_CONFIG" --list-profiles extra >/dev/null 2>&1; then
  echo "FAIL: expected failure for extra args"
  failures=$((failures + 1))
else
  echo "PASS"
fi

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All orch-config tests passed."
else
  echo "${failures} test(s) failed."
  exit 1
fi
