#!/usr/bin/env bash
set -euo pipefail

# test_board_onboard_lite.sh — verify board-onboard-lite exists and board-run-ready documents .task-spec.md

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LITE_SKILL="$REPO_ROOT/skills/board-onboard-lite/SKILL.md"
RUN_READY_SKILL="$REPO_ROOT/skills/board-run-ready/SKILL.md"
ORCHESTRATOR_DOC="$REPO_ROOT/docs/ORCHESTRATOR.md"

echo "--- Test 1: board-onboard-lite SKILL.md exists ---"
if [[ -f "$LITE_SKILL" ]]; then
  echo "PASS"
else
  echo "FAIL: board-onboard-lite SKILL.md not found"
  exit 1
fi

echo "--- Test 2: board-onboard-lite has required frontmatter ---"
if grep -q "name: board-onboard-lite" "$LITE_SKILL"; then
  echo "PASS"
else
  echo "FAIL: missing name in frontmatter"
  exit 1
fi

echo "--- Test 3: board-onboard-lite links to docs/ORCHESTRATOR.md ---"
if grep -q "ORCHESTRATOR.md" "$LITE_SKILL"; then
  echo "PASS"
else
  echo "FAIL: no link to ORCHESTRATOR.md"
  exit 1
fi

echo "--- Test 4: docs/ORCHESTRATOR.md exists ---"
if [[ -f "$ORCHESTRATOR_DOC" ]]; then
  echo "PASS"
else
  echo "FAIL: docs/ORCHESTRATOR.md not found"
  exit 1
fi

echo "--- Test 5: docs/ORCHESTRATOR.md has task spec format ---"
if grep -q ".task-spec.md" "$ORCHESTRATOR_DOC" && \
   grep -q "forbidden_reads" "$ORCHESTRATOR_DOC"; then
  echo "PASS"
else
  echo "FAIL: missing .task-spec.md format in ORCHESTRATOR.md"
  exit 1
fi

echo "--- Test 6: board-run-ready documents .task-spec.md generation ---"
if grep -q ".task-spec.md" "$RUN_READY_SKILL"; then
  echo "PASS"
else
  echo "FAIL: board-run-ready does not mention .task-spec.md"
  exit 1
fi

echo "--- Test 7: board-run-ready documents forbidden_reads ---"
if grep -q "forbidden_reads" "$RUN_READY_SKILL"; then
  echo "PASS"
else
  echo "FAIL: board-run-ready does not document forbidden_reads"
  exit 1
fi

echo "--- Test 8: board-run-ready has Step 0 for generating spec ---"
if grep -q "Step 0" "$RUN_READY_SKILL" || \
   grep -q "Generate.*task-spec" "$RUN_READY_SKILL"; then
  echo "PASS"
else
  echo "FAIL: no Step 0 for generating .task-spec.md"
  exit 1
fi

echo "--- Test 9: ORCHESTRATOR.md has delegation cycle ---"
if grep -q "delegation cycle" "$ORCHESTRATOR_DOC" || \
   grep -q "cmux delegation cycle" "$ORCHESTRATOR_DOC"; then
  echo "PASS"
else
  echo "FAIL: missing delegation cycle in ORCHESTRATOR.md"
  exit 1
fi

echo ""
echo "All board-onboard-lite / task-spec tests passed."
