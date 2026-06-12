#!/usr/bin/env bash
# Tests for reflow-tolerant pi agent readiness probe (#54).
# Verifies that stripping ALL whitespace + box-drawing chars correctly detects
# the pi TUI even when it renders as multi-column boxes in narrow panes.
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

# Simulate the wait_agent_ready normalization logic for pi:
# aggressive strip of whitespace + box-drawing chars
normalize_screen() {
  printf '%s' "$1" | tr -d '[:space:]┃┏┓┗┛━╹▀│─┌┐└┘●'
}

pi_pattern="$(agent_ready_patterns pi)"

# ── Test 1: Real pi-ready fixture matches (auto)/(sub) pattern ──
echo "=== Test 1: pi-ready fixture ACCEPTED ==="
fixture="$(cat "$FIXTURE")"
normalized="$(normalize_screen "$fixture")"
if grep -qE "$pi_pattern" <<<"$normalized"; then
  echo "PASS"
else
  echo "FAIL: pi pattern should accept pi-ready fixture"
  failures=$((failures + 1))
fi

# ── Test 2: Normal (wide) pi prompt — pattern accepts ──
echo "=== Test 2: Normal pi prompt accepted ==="
normal_screen='(auto) esc to interrupt  pi ready'
normal_norm="$(normalize_screen "$normal_screen")"
if grep -qE "$pi_pattern" <<<"$normal_norm"; then
  echo "PASS"
else
  echo "FAIL: normal pi prompt should match pattern"
  failures=$((failures + 1))
fi

# ── Test 3: Bare shell line — pattern REJECTS (no false positive) ──
echo "=== Test 3: Bare shell rejected ==="
shell_screen='user@host ~ % '
shell_norm="$(normalize_screen "$shell_screen")"
if grep -qE "$pi_pattern" <<<"$shell_norm"; then
  echo "FAIL: bare shell line should not match"
  failures=$((failures + 1))
else
  echo "PASS"
fi

# ── Test 4: pi prompt with (sub) marker — pattern accepts ──
echo "=== Test 4: (sub) pi prompt accepted ==="
sub_screen='(sub) pi agent session'
sub_norm="$(normalize_screen "$sub_screen")"
if grep -qE "$pi_pattern" <<<"$sub_norm"; then
  echo "PASS"
else
  echo "FAIL: (sub) pi prompt should match"
  failures=$((failures + 1))
fi

# ── Test 5: Narrow reflow stress — box-drawing chars stripped, pattern survives ──
echo "=== Test 5: narrow-reflow stress ==="
reflow_screen='┃ (auto) ┃ ┃ esc ┃ ┃ interrupt ┃'
reflow_norm="$(normalize_screen "$reflow_screen")"
if grep -qE "$pi_pattern" <<<"$reflow_norm"; then
  echo "PASS"
else
  echo "FAIL: narrow-reflow pi prompt should match"
  failures=$((failures + 1))
fi

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All agent readiness probe tests passed."
else
  echo "$failures test(s) failed."
  exit 1
fi
