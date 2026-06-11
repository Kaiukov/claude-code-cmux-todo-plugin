#!/usr/bin/env bash
set -euo pipefail

# test_board_plan_cap.sh — verify board-plan SKILL.md documents the cap and summary

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLAN_SKILL="$REPO_ROOT/skills/board-plan/SKILL.md"

if [[ ! -f "$PLAN_SKILL" ]]; then
  echo "FAIL: board-plan SKILL.md not found at $PLAN_SKILL"
  exit 1
fi

echo "--- Test 1: board-plan mentions the cap of 5 ---"
if grep -q "Cap: 5 ready tasks mirrored" "$PLAN_SKILL" || \
   grep -q "Mirror up to.*5.*ready" "$PLAN_SKILL" || \
   grep -q "cap.*5" "$PLAN_SKILL"; then
  echo "PASS"
else
  echo "FAIL: cap of 5 not documented in board-plan"
  exit 1
fi

echo "--- Test 2: board-plan mentions summary line for overflow ---"
if grep -q "N more ready tasks" "$PLAN_SKILL" || \
   grep -q "see board.json" "$PLAN_SKILL" || \
   grep -q "summary line" "$PLAN_SKILL"; then
  echo "PASS"
else
  echo "FAIL: summary line not documented in board-plan"
  exit 1
fi

echo "--- Test 3: board-plan mentions max 5 ready mirrored ---"
if grep -q "first 5" "$PLAN_SKILL" || grep -q "up to.*5" "$PLAN_SKILL" || grep -q "more than 5" "$PLAN_SKILL"; then
  echo "PASS"
else
  echo "FAIL: max 5 not documented in board-plan"
  exit 1
fi

echo ""
echo "All board-plan cap tests passed."
