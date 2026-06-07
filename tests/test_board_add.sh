#!/usr/bin/env bash
set -euo pipefail

# test_board_add.sh — self-contained test for bin/board-add
# No network; uses a minimal fake issues.json so render can run.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOARD_ADD="$REPO_ROOT/bin/board-add"

if [[ ! -f "$BOARD_ADD" ]]; then
  echo "FAIL: board-add not found at $BOARD_ADD"
  exit 1
fi

run_add() {
  (cd "$TMPDIR" && bash "$BOARD_ADD" "$@")
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Setup: mimic repo with a minimal issues.json so render runs
mkdir -p "$TMPDIR/.tasks"
echo '[]' > "$TMPDIR/.tasks/issues.json"

echo "--- Test 1: add task with default status (L1) ---"
run_add "deploy to dev" 2>/dev/null
if [[ ! -f "$TMPDIR/.tasks/local.json" ]]; then
  echo "FAIL: local.json was not created"
  exit 1
fi
id=$(jq -r '.[0].id' "$TMPDIR/.tasks/local.json")
status=$(jq -r '.[0].status' "$TMPDIR/.tasks/local.json")
title=$(jq -r '.[0].title' "$TMPDIR/.tasks/local.json")
if [[ "$id" == "L1" && "$status" == "ready" && "$title" == "deploy to dev" ]]; then
  echo "PASS"
else
  echo "FAIL: got id=$id status=$status title=$title"
  exit 1
fi

echo "--- Test 2: add second task with explicit status (L2) ---"
run_add --status "in-progress" "fix login bug" 2>/dev/null
len=$(jq '. | length' "$TMPDIR/.tasks/local.json")
if [[ "$len" == "2" ]]; then
  echo "PASS"
else
  echo "FAIL: expected 2 tasks, got $len"
  exit 1
fi
id2=$(jq -r '.[1].id' "$TMPDIR/.tasks/local.json")
status2=$(jq -r '.[1].status' "$TMPDIR/.tasks/local.json")
title2=$(jq -r '.[1].title' "$TMPDIR/.tasks/local.json")
if [[ "$id2" == "L2" && "$status2" == "in-progress" && "$title2" == "fix login bug" ]]; then
  echo "PASS"
else
  echo "FAIL: got id=$id2 status=$status2 title=$title2"
  exit 1
fi

echo "--- Test 3: reject invalid status ---"
if run_add --status "bogus" "some task" 2>/dev/null; then
  echo "FAIL: expected non-zero exit for bogus status"
  exit 1
fi
echo "PASS"

echo "--- Test 4: --list shows tasks ---"
list_out=$(run_add --list)
if echo "$list_out" | grep -q "L1 \[ready\] deploy to dev" && \
   echo "$list_out" | grep -q "L2 \[in-progress\] fix login bug"; then
  echo "PASS"
else
  echo "FAIL: list output:"
  echo "$list_out"
  exit 1
fi

echo "--- Test 5: --remove a task ---"
run_add --remove L1 2>/dev/null
len_after=$(jq '. | length' "$TMPDIR/.tasks/local.json")
if [[ "$len_after" == "1" ]]; then
  echo "PASS"
else
  echo "FAIL: expected 1 task after remove, got $len_after"
  exit 1
fi

echo "--- Test 6: --remove nonexistent id ---"
if run_add --remove L99 2>/dev/null; then
  echo "FAIL: expected error for nonexistent id"
  exit 1
fi
echo "PASS"

echo "--- Test 7: auto-id continues after gap (add after remove) ---"
run_add "third task" 2>/dev/null
new_id=$(jq -r '.[-1].id' "$TMPDIR/.tasks/local.json")
if [[ "$new_id" == "L3" ]]; then
  echo "PASS"
else
  echo "FAIL: expected L3, got $new_id"
  exit 1
fi

echo "--- Test 8: board.json has local tasks with source:local ---"
board_len=$(jq '. | length' "$TMPDIR/.tasks/board.json")
if [[ "$board_len" == "2" ]]; then
  echo "PASS"
else
  echo "FAIL: expected 2 tasks in board.json, got $board_len"
  exit 1
fi
local_count=$(jq '[.[] | select(.source=="local")] | length' "$TMPDIR/.tasks/board.json")
if [[ "$local_count" == "2" ]]; then
  echo "PASS"
else
  echo "FAIL: expected 2 local tasks in board.json, got $local_count"
  exit 1
fi

echo ""
echo "All board-add tests passed."
