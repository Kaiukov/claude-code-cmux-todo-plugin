#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOARD_NEXT="$REPO_ROOT/bin/board-next"

if [[ ! -f "$BOARD_NEXT" ]]; then
  echo "FAIL: board-next not found at $BOARD_NEXT"
  exit 1
fi

run_next() {
  (cd "$TMPDIR" && bash "$BOARD_NEXT" "$@")
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/.tasks"

echo "--- Test 1: missing board.json --- exit 1 ---"
if run_next 2>/dev/null; then
  echo "FAIL: expected non-zero exit for missing board.json"
  exit 1
fi
echo "PASS"

echo "--- Test 2: default (ready) returns first ready github task ---"
cat > "$TMPDIR/.tasks/board.json" <<'BOARDEOF'
[
  {"number": 1, "id": null, "title": "initial setup", "status": "inbox", "labels": ["inbox"], "url": "https://github.com/owner/repo/issues/1", "assignees": [], "source": "github"},
  {"number": 8, "id": null, "title": "feat: /board-add-task", "status": "ready", "labels": ["ready"], "url": "https://github.com/owner/repo/issues/8", "assignees": [], "source": "github"},
  {"number": 2, "id": null, "title": "fix login bug", "status": "ready", "labels": ["ready"], "url": "https://github.com/owner/repo/issues/2", "assignees": ["alice"], "source": "github"},
  {"number": 3, "id": null, "title": "done task", "status": "done", "labels": ["done"], "url": "https://github.com/owner/repo/issues/3", "assignees": [], "source": "github"}
]
BOARDEOF

output=$(run_next)
if [[ "$output" == "#8 feat: /board-add-task" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$output', expected '#8 feat: /board-add-task'"
  exit 1
fi

echo "--- Test 3: --status inbox ---"
output=$(run_next --status inbox)
if [[ "$output" == "#1 initial setup" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$output', expected '#1 initial setup'"
  exit 1
fi

echo "--- Test 4: invalid status --- exit 1 ---"
if run_next --status bogus 2>/dev/null; then
  echo "FAIL: expected non-zero exit for bogus status"
  exit 1
fi
echo "PASS"

echo "--- Test 5: --json returns full board.json entry ---"
json_output=$(run_next --json)
number=$(echo "$json_output" | jq -r '.number')
id_field=$(echo "$json_output" | jq -r '.id')
title=$(echo "$json_output" | jq -r '.title')
status=$(echo "$json_output" | jq -r '.status')
source=$(echo "$json_output" | jq -r '.source')
if [[ "$number" == "8" && "$id_field" == "null" && "$title" == "feat: /board-add-task" && "$status" == "ready" && "$source" == "github" ]]; then
  echo "PASS"
else
  echo "FAIL: got number=$number id=$id_field title=$title status=$status source=$source"
  exit 1
fi

echo "--- Test 6: empty case — (none) / null ---"
cat > "$TMPDIR/.tasks/board.json" <<'BOARDEOF'
[
  {"number": 1, "id": null, "title": "done task", "status": "done", "labels": ["done"], "url": "https://github.com/owner/repo/issues/1", "assignees": [], "source": "github"}
]
BOARDEOF

output=$(run_next)
if [[ "$output" == "(none)" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$output', expected '(none)'"
  exit 1
fi

json_output=$(run_next --json)
if [[ "$(echo "$json_output" | jq -c '.')" == "null" ]]; then
  echo "PASS"
else
  echo "FAIL: expected null, got $(echo "$json_output" | jq -c '.')"
  exit 1
fi

echo "--- Test 7: local task selection ---"
cat > "$TMPDIR/.tasks/board.json" <<'BOARDEOF'
[
  {"number": 1, "id": null, "title": "initial setup", "status": "inbox", "labels": ["inbox"], "url": "https://github.com/owner/repo/issues/1", "assignees": [], "source": "github"},
  {"number": null, "id": "L1", "title": "deploy to dev", "status": "ready", "labels": [], "url": "", "assignees": [], "source": "local"}
]
BOARDEOF

output=$(run_next)
if [[ "$output" == "L1 deploy to dev" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$output', expected 'L1 deploy to dev'"
  exit 1
fi

json_output=$(run_next --json)
number=$(echo "$json_output" | jq -r '.number')
id_field=$(echo "$json_output" | jq -r '.id')
title=$(echo "$json_output" | jq -r '.title')
source=$(echo "$json_output" | jq -r '.source')
if [[ "$number" == "null" && "$id_field" == "L1" && "$title" == "deploy to dev" && "$source" == "local" ]]; then
  echo "PASS"
else
  echo "FAIL: got number=$number id=$id_field title=$title source=$source"
  exit 1
fi

echo "--- Test 8: --help flag ---"
if run_next --help 2>/dev/null | grep -q "Usage:"; then
  echo "PASS"
else
  echo "FAIL: --help did not show usage"
  exit 1
fi

echo "--- Test 9: --status done with empty result ---"
cat > "$TMPDIR/.tasks/board.json" <<'BOARDEOF'
[
  {"number": 1, "id": null, "title": "initial setup", "status": "inbox", "labels": ["inbox"], "url": "https://github.com/owner/repo/issues/1", "assignees": [], "source": "github"}
]
BOARDEOF

output=$(run_next --status done)
if [[ "$output" == "(none)" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$output', expected '(none)'"
  exit 1
fi

echo ""
echo "All board-next tests passed."
