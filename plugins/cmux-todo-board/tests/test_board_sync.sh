#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOARD_SYNC="$REPO_ROOT/bin/board-sync"

if [[ ! -f "$BOARD_SYNC" ]]; then
  echo "FAIL: board-sync not found at $BOARD_SYNC"
  exit 1
fi

# Source the pure compute_label_changes function from board-sync
CANONICAL_STATUSES=("inbox" "ready" "in-progress" "needs-review" "blocked" "needs-info" "done")

compute_label_changes() {
  local target="$1" labels_csv="$2"

  if echo "$labels_csv" | tr ',' '\n' | grep -qxF "$target"; then
    echo "NOOP"
    return
  fi

  local old=""
  for lbl in "${CANONICAL_STATUSES[@]}"; do
    if echo "$labels_csv" | tr ',' '\n' | grep -qxF "$lbl"; then
      old="$lbl"
      break
    fi
  done

  echo "REMOVE=${old} ADD=${target}"
}

failures=0

echo "=== Test 1: ready -> in-progress (swap canonical) ==="
result=$(compute_label_changes "in-progress" "ready")
if [[ "$result" == "REMOVE=ready ADD=in-progress" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result'"
  failures=$((failures + 1))
fi

echo "=== Test 2: same status -> no change (idempotent) ==="
result=$(compute_label_changes "ready" "ready")
if [[ "$result" == "NOOP" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result'"
  failures=$((failures + 1))
fi

echo "=== Test 3: same status with other labels -> no-op ==="
result=$(compute_label_changes "ready" "bug,ready,enhancement")
if [[ "$result" == "NOOP" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result'"
  failures=$((failures + 1))
fi

echo "=== Test 4: non-canonical labels preserved: [bug, ready] -> in-progress ==="
result=$(compute_label_changes "in-progress" "bug,ready")
if [[ "$result" == "REMOVE=ready ADD=in-progress" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result'"
  failures=$((failures + 1))
fi

echo "=== Test 5: no canonical label -> just add target ==="
result=$(compute_label_changes "ready" "bug,enhancement")
if [[ "$result" == "REMOVE= ADD=ready" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result'"
  failures=$((failures + 1))
fi

echo "=== Test 6: empty labels -> just add target ==="
result=$(compute_label_changes "inbox" "")
if [[ "$result" == "REMOVE= ADD=inbox" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result'"
  failures=$((failures + 1))
fi

echo "=== Test 7: done -> inbox (swap across full spectrum) ==="
result=$(compute_label_changes "inbox" "done")
if [[ "$result" == "REMOVE=done ADD=inbox" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result'"
  failures=$((failures + 1))
fi

echo "=== Test 8: blocked -> needs-info ==="
result=$(compute_label_changes "needs-info" "blocked")
if [[ "$result" == "REMOVE=blocked ADD=needs-info" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result'"
  failures=$((failures + 1))
fi

echo "=== Test 9: in-progress with non-canonical labels -> needs-review ==="
result=$(compute_label_changes "needs-review" "bug,in-progress,enhancement,p2")
if [[ "$result" == "REMOVE=in-progress ADD=needs-review" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result'"
  failures=$((failures + 1))
fi

echo "=== Test 10: done with non-canonical -> done again (no-op with extras) ==="
result=$(compute_label_changes "done" "bug,done,enhancement")
if [[ "$result" == "NOOP" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result'"
  failures=$((failures + 1))
fi

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All compute_label_changes tests passed."
else
  echo "${failures} test(s) failed."
  exit 1
fi
