#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIMIT_MONITOR="$REPO_ROOT/bin/limit-monitor"

if [[ ! -f "$LIMIT_MONITOR" ]]; then
  echo "FAIL: limit-monitor not found at $LIMIT_MONITOR"
  exit 1
fi

FAILURES=0

run_monitor() {
  local input_json="$1" data_file="$2" surface_arg="${3:-}"
  if [[ -n "$surface_arg" ]]; then
    LIMIT_DATA_FILE="$data_file" "$LIMIT_MONITOR" --surface "$surface_arg" <<< "$input_json"
  else
    LIMIT_DATA_FILE="$data_file" "$LIMIT_MONITOR" <<< "$input_json"
  fi
}

mkdir -p "$REPO_ROOT/.tasks"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=== Test 1: 80% input → WARN, state recorded ==="
DATA1="$TMP/data1.json"
INPUT80='{"rate_limits":{"seven_day":{"used_percentage":80,"resets_at":1774580400}}}'
output1=$(run_monitor "$INPUT80" "$DATA1" 2>&1) || true
if echo "$output1" | grep -q "WARN.*80%"; then
  echo "PASS: WARN message found"
else
  echo "FAIL: no WARN message in: $output1"
  FAILURES=$((FAILURES + 1))
fi
if [[ -f "$DATA1" ]]; then
  alerted=$(jq -r '.seven_day.alerted_at_thresholds | join(",")' "$DATA1")
  if [[ "$alerted" == "80" ]]; then
    echo "PASS: alerted_at_thresholds contains 80"
  else
    echo "FAIL: alerted_at_thresholds = $alerted (expected 80)"
    FAILURES=$((FAILURES + 1))
  fi
else
  echo "FAIL: state file not created"
  FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 2: 95% input → CRIT + WARN, state recorded ==="
DATA2="$TMP/data2.json"
INPUT95='{"rate_limits":{"seven_day":{"used_percentage":95,"resets_at":1774580400}}}'
output2=$(run_monitor "$INPUT95" "$DATA2" 2>&1) || true
if echo "$output2" | grep -q "CRIT.*95%"; then
  echo "PASS: CRIT message found"
else
  echo "FAIL: no CRIT message in: $output2"
  FAILURES=$((FAILURES + 1))
fi
if echo "$output2" | grep -q "WARN.*95%"; then
  echo "PASS: WARN message also present"
else
  echo "FAIL: no WARN message in: $output2"
  FAILURES=$((FAILURES + 1))
fi
alerted2=$(jq -r '.seven_day.alerted_at_thresholds | join(",")' "$DATA2")
if [[ "$alerted2" == "95,80" ]]; then
  echo "PASS: alerted_at_thresholds contains 95,80"
else
  echo "FAIL: alerted_at_thresholds = $alerted2 (expected 95,80)"
  FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 3: absent rate_limits → exit 0, stderr notice ==="
DATA3="$TMP/data3.json"
INPUT_NO_RATE='{"model":"claude-sonnet-4-6"}'
output3=$(run_monitor "$INPUT_NO_RATE" "$DATA3" 2>&1); rc=$?
if [[ $rc -eq 0 ]]; then
  echo "PASS: exit code 0"
else
  echo "FAIL: exit code $rc (expected 0)"
  FAILURES=$((FAILURES + 1))
fi
if echo "$output3" | grep -q "rate_limits.seven_day not available"; then
  echo "PASS: stderr notice found"
else
  echo "FAIL: no stderr notice in: $output3"
  FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 4: week rollover → alerted_at_thresholds reset ==="
DATA4="$TMP/data4.json"
INPUT_W1='{"rate_limits":{"seven_day":{"used_percentage":81,"resets_at":1000}}}'
INPUT_W2='{"rate_limits":{"seven_day":{"used_percentage":81,"resets_at":2000}}}'
output4a=$(run_monitor "$INPUT_W1" "$DATA4" 2>&1) || true
alerted4a=$(jq -r '.seven_day.alerted_at_thresholds | join(",")' "$DATA4")
if [[ "$alerted4a" == "80" ]]; then
  echo "PASS (week1): WARN recorded as 80"
else
  echo "FAIL (week1): alerted = $alerted4a (expected 80)"
  FAILURES=$((FAILURES + 1))
fi
output4b=$(run_monitor "$INPUT_W2" "$DATA4" 2>&1) || true
alerted4b=$(jq -r '.seven_day.alerted_at_thresholds | join(",")' "$DATA4")
if [[ "$alerted4b" == "80" ]]; then
  echo "PASS (week2): alerted cleared, WARN re-recorded"
else
  echo "FAIL (week2): alerted = $alerted4b (expected 80 after reset)"
  FAILURES=$((FAILURES + 1))
fi

echo ""
echo "=== Test 5: dedup — same threshold not re-alerted ==="
DATA5="$TMP/data5.json"
INPUT_DEDUP1='{"rate_limits":{"seven_day":{"used_percentage":82,"resets_at":3000}}}'
INPUT_DEDUP2='{"rate_limits":{"seven_day":{"used_percentage":87,"resets_at":3000}}}'
run_monitor "$INPUT_DEDUP1" "$DATA5" > /dev/null 2>&1 || true
output5b=$(run_monitor "$INPUT_DEDUP2" "$DATA5" 2>&1) || true
if echo "$output5b" | grep -q "WARN"; then
  echo "FAIL: WARN fired twice for same week"
  FAILURES=$((FAILURES + 1))
else
  echo "PASS: WARN not re-fired (dedup works)"
fi

echo ""
if [[ $FAILURES -eq 0 ]]; then
  echo "All limit-monitor tests passed."
else
  echo "$FAILURES test(s) failed."
  exit 1
fi
