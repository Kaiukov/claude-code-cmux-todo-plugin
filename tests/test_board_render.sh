#!/usr/bin/env bash
set -euo pipefail

# test_board_render.sh — self-contained test for bin/board-render
# Uses tests/fixtures/issues.sample.json as input into a temp directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDER_SCRIPT="$REPO_ROOT/bin/board-render"

if [[ ! -f "$RENDER_SCRIPT" ]]; then
  echo "FAIL: board-render not found at $RENDER_SCRIPT"
  exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Setup: mimic repo structure
mkdir -p "$TMPDIR/.tasks"
cp "$SCRIPT_DIR/fixtures/issues.sample.json" "$TMPDIR/.tasks/issues.json"

run_render() {
  (cd "$TMPDIR" && python3 "$RENDER_SCRIPT")
}

echo "--- Test 1: board.json is created ---"
run_render 2>/dev/null
if [[ ! -f "$TMPDIR/.tasks/board.json" ]]; then
  echo "FAIL: board.json was not created"
  exit 1
fi
echo "PASS"

echo "--- Test 2: board.json has expected statuses (9 issues, incl. null labels + multi-label) ---"
statuses=$(python3 -c "import json; data=json.load(open('$TMPDIR/.tasks/board.json')); print(' '.join(t['status'] for t in data))")
expected_statuses="inbox inbox ready ready in-progress needs-review blocked needs-info done"
if [[ "$statuses" == "$expected_statuses" ]]; then
  echo "PASS"
else
  echo "FAIL: got statuses: $statuses"
  echo "      expected: $expected_statuses"
  exit 1
fi

echo "--- Test 3: TODO.md is created ---"
if [[ ! -f "$TMPDIR/TODO.md" ]]; then
  echo "FAIL: TODO.md was not created"
  exit 1
fi
echo "PASS"

echo "--- Test 4: TODO.md has 'do not edit' header ---"
if head -1 "$TMPDIR/TODO.md" | grep -q "do not edit"; then
  echo "PASS"
else
  echo "FAIL: header not found"
  head -1 "$TMPDIR/TODO.md"
  exit 1
fi

echo "--- Test 5: TODO.md groups are in canonical order ---"
# Extract status headings in order
headings=$(grep '^## ' "$TMPDIR/TODO.md" | sed 's/^## //')
expected_headings=$(printf "inbox\nready\nin-progress\nneeds-review\nblocked\nneeds-info\ndone")
if [[ "$headings" == "$expected_headings" ]]; then
  echo "PASS"
else
  echo "FAIL: got headings:"
  echo "$headings"
  echo "expected:"
  echo "$expected_headings"
  exit 1
fi

echo "--- Test 6: Determinism — second run produces byte-identical output ---"
# Copy first output
cp "$TMPDIR/TODO.md" "$TMPDIR/TODO.md.first"
cp "$TMPDIR/.tasks/board.json" "$TMPDIR/.tasks/board.json.first"
# Re-run
run_render 2>/dev/null
# Compare
if diff "$TMPDIR/TODO.md.first" "$TMPDIR/TODO.md" >/dev/null 2>&1 && \
   diff "$TMPDIR/.tasks/board.json.first" "$TMPDIR/.tasks/board.json" >/dev/null 2>&1; then
  echo "PASS"
else
  echo "FAIL: output differs between runs"
  echo "TODO.md diff:"
  diff "$TMPDIR/TODO.md.first" "$TMPDIR/TODO.md" || true
  echo "board.json diff:"
  diff "$TMPDIR/.tasks/board.json.first" "$TMPDIR/.tasks/board.json" || true
  exit 1
fi

echo "--- Test 7: Null labels default to inbox ---"
null_status=$(python3 -c "import json; data=json.load(open('$TMPDIR/.tasks/board.json')); issue8=[t for t in data if t['number']==8][0]; print(issue8['status'])")
if [[ "$null_status" == "inbox" ]]; then
  echo "PASS"
else
  echo "FAIL: issue #8 (null labels) got status '$null_status', expected 'inbox'"
  exit 1
fi

echo "--- Test 8: Multi-label priority — ready wins over inbox ---"
multi_status=$(python3 -c "import json; data=json.load(open('$TMPDIR/.tasks/board.json')); issue9=[t for t in data if t['number']==9][0]; print(issue9['status'])")
if [[ "$multi_status" == "ready" ]]; then
  echo "PASS"
else
  echo "FAIL: issue #9 (inbox + ready) got status '$multi_status', expected 'ready'"
  exit 1
fi

echo ""
echo "All tests passed."
