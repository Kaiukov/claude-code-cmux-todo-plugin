#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOARD_STATUS="$REPO_ROOT/bin/board-status"

if [[ ! -f "$BOARD_STATUS" ]]; then
  echo "FAIL: board-status not found at $BOARD_STATUS"
  exit 1
fi

run_status() {
  (cd "$TMPDIR" && bash "$BOARD_STATUS" "$@")
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.tasks"

echo "--- Test 1: missing board.json --- exit 1 ---"
if run_status 2>/dev/null; then
  echo "FAIL: expected non-zero exit for missing board.json"
  exit 1
fi
echo "PASS"

echo "--- Test 2: human output — full counts line + next_ready ---"
cat > "$TMPDIR/.tasks/board.json" <<'BOARDEOF'
[
  {"number": 1, "id": null, "title": "initial setup", "status": "inbox", "labels": ["inbox"], "url": "https://github.com/owner/repo/issues/1", "assignees": [], "source": "github"},
  {"number": 8, "id": null, "title": "feat: /board-add-task", "status": "ready", "labels": ["ready"], "url": "https://github.com/owner/repo/issues/8", "assignees": [], "source": "github"},
  {"number": 2, "id": null, "title": "fix login bug", "status": "ready", "labels": ["ready"], "url": "https://github.com/owner/repo/issues/2", "assignees": ["alice"], "source": "github"},
  {"number": 9, "id": null, "title": "in-progress feature", "status": "in-progress", "labels": ["in-progress"], "url": "https://github.com/owner/repo/issues/9", "assignees": [], "source": "github"},
  {"number": null, "id": "L1", "title": "deploy to dev", "status": "ready", "labels": [], "url": "", "assignees": [], "source": "local"},
  {"number": 3, "id": null, "title": "needs code review", "status": "needs-review", "labels": ["needs-review"], "url": "https://github.com/owner/repo/issues/3", "assignees": [], "source": "github"},
  {"number": 4, "id": null, "title": "waiting for API", "status": "blocked", "labels": ["blocked"], "url": "https://github.com/owner/repo/issues/4", "assignees": [], "source": "github"},
  {"number": 5, "id": null, "title": "need docs", "status": "needs-info", "labels": ["needs-info"], "url": "https://github.com/owner/repo/issues/5", "assignees": [], "source": "github"},
  {"number": 6, "id": null, "title": "shipped!", "status": "done", "labels": ["done"], "url": "https://github.com/owner/repo/issues/6", "assignees": [], "source": "github"}
]
BOARDEOF

output=$(run_status)
counts_line=$(echo "$output" | head -1)
expected_counts="inbox=1 ready=3 in-progress=1 needs-review=1 blocked=1 needs-info=1 done=1"
if [[ "$counts_line" == "$expected_counts" ]]; then
  echo "PASS"
else
  echo "FAIL: got counts:  $counts_line"
  echo "      expected: $expected_counts"
  exit 1
fi

next_line=$(echo "$output" | tail -1)
expected_next="next_ready=#8 feat: /board-add-task"
if [[ "$next_line" == "$expected_next" ]]; then
  echo "PASS"
else
  echo "FAIL: got next:  $next_line"
  echo "      expected: $expected_next"
  exit 1
fi

echo "--- Test 3: --json output has correct shape ---"
json_output=$(run_status --json)
inbox_count=$(echo "$json_output" | jq -r '.counts.inbox')
ready_count=$(echo "$json_output" | jq -r '.counts.ready')
if [[ "$inbox_count" == "1" && "$ready_count" == "3" ]]; then
  echo "PASS"
else
  echo "FAIL: got inbox=$inbox_count ready=$ready_count"
  exit 1
fi

in_progress_count=$(echo "$json_output" | jq -r '.counts.in_progress')
needs_review_count=$(echo "$json_output" | jq -r '.counts.needs_review')
needs_info_count=$(echo "$json_output" | jq -r '.counts.needs_info')
done_count=$(echo "$json_output" | jq -r '.counts.done')
blocked_count=$(echo "$json_output" | jq -r '.counts.blocked')
if [[ "$in_progress_count" == "1" && "$needs_review_count" == "1" && "$blocked_count" == "1" && "$needs_info_count" == "1" && "$done_count" == "1" ]]; then
  echo "PASS"
else
  echo "FAIL: got in_progress=$in_progress_count needs_review=$needs_review_count blocked=$blocked_count needs_info=$needs_info_count done=$done_count"
  exit 1
fi

next_number=$(echo "$json_output" | jq -r '.next_ready.number')
next_id=$(echo "$json_output" | jq -r '.next_ready.id')
next_title=$(echo "$json_output" | jq -r '.next_ready.title')
if [[ "$next_number" == "8" && "$next_id" == "null" && "$next_title" == "feat: /board-add-task" ]]; then
  echo "PASS"
else
  echo "FAIL: got next_ready number=$next_number id=$next_id title=$next_title"
  exit 1
fi

echo "--- Test 4: no ready tasks — (none) / null ---"
cat > "$TMPDIR/.tasks/board.json" <<'BOARDEOF'
[
  {"number": 1, "id": null, "title": "initial setup", "status": "inbox", "labels": ["inbox"], "url": "https://github.com/owner/repo/issues/1", "assignees": [], "source": "github"},
  {"number": 2, "id": null, "title": "done task", "status": "done", "labels": ["done"], "url": "https://github.com/owner/repo/issues/2", "assignees": [], "source": "github"}
]
BOARDEOF

output=$(run_status)
next_line=$(echo "$output" | tail -1)
if [[ "$next_line" == "next_ready=(none)" ]]; then
  echo "PASS"
else
  echo "FAIL: got $next_line, expected next_ready=(none)"
  exit 1
fi

json_output=$(run_status --json)
next_ready_val=$(echo "$json_output" | jq -r '.next_ready')
if [[ "$next_ready_val" == "null" ]]; then
  echo "PASS"
else
  echo "FAIL: expected null for next_ready, got $next_ready_val"
  exit 1
fi

echo "--- Test 5: local task as next_ready ---"
cat > "$TMPDIR/.tasks/board.json" <<'BOARDEOF'
[
  {"number": 1, "id": null, "title": "initial setup", "status": "inbox", "labels": ["inbox"], "url": "https://github.com/owner/repo/issues/1", "assignees": [], "source": "github"},
  {"number": null, "id": "L1", "title": "local ready task", "status": "ready", "labels": [], "url": "", "assignees": [], "source": "local"}
]
BOARDEOF

output=$(run_status)
next_line=$(echo "$output" | tail -1)
if [[ "$next_line" == "next_ready=L1 local ready task" ]]; then
  echo "PASS"
else
  echo "FAIL: got $next_line, expected next_ready=L1 local ready task"
  exit 1
fi

json_output=$(run_status --json)
next_number=$(echo "$json_output" | jq -r '.next_ready.number')
next_id=$(echo "$json_output" | jq -r '.next_ready.id')
next_title=$(echo "$json_output" | jq -r '.next_ready.title')
if [[ "$next_number" == "null" && "$next_id" == "L1" && "$next_title" == "local ready task" ]]; then
  echo "PASS"
else
  echo "FAIL: got number=$next_number id=$next_id title=$next_title"
  exit 1
fi

echo "--- Test 6: --help flag ---"
if run_status --help 2>/dev/null | grep -q "Usage:"; then
  echo "PASS"
else
  echo "FAIL: --help did not show usage"
  exit 1
fi

echo ""
echo "All board-status tests passed."
