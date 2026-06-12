#!/usr/bin/env bash
set -euo pipefail

# test_board_render_body.sh — test board-render-body on-demand body retrieval

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDER_BODY="$REPO_ROOT/bin/board-render-body"

if [[ ! -f "$RENDER_BODY" ]]; then
  echo "FAIL: board-render-body not found at $RENDER_BODY"
  exit 1
fi

run_render_body() {
  (cd "$TMPDIR" && bash "$RENDER_BODY" "$@")
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "--- Test 1: retrieves cached body from issues.json ---"
mkdir -p "$TMPDIR/.tasks"
cat > "$TMPDIR/.tasks/issues.json" <<'ISSUESEOF'
[
  {"number": 42, "title": "test issue", "url": "https://x/42", "labels": [{"name": "ready"}], "body": "this is the body"}
]
ISSUESEOF
cat > "$TMPDIR/.tasks/board.json" <<'BOARDEOF'
[
  {"number": 42, "id": null, "title": "test issue", "status": "ready", "labels": ["ready"], "url": "https://x/42", "assignees": [], "source": "github", "updatedAt": "", "body_sha": "", "body_preview": "this is the body"}
]
BOARDEOF

output=$(run_render_body "42")
if echo "$output" | grep -q "this is the body"; then
  echo "PASS"
else
  echo "FAIL: got '$output', expected body content"
  exit 1
fi

echo "--- Test 2: writes .tasks/issues/42.md ---"
if [[ -f "$TMPDIR/.tasks/issues/42.md" ]]; then
  if grep -q "# #42 test issue" "$TMPDIR/.tasks/issues/42.md" && \
     grep -q "this is the body" "$TMPDIR/.tasks/issues/42.md"; then
    echo "PASS"
  else
    echo "FAIL: .md content wrong:"
    cat "$TMPDIR/.tasks/issues/42.md"
    exit 1
  fi
else
  echo "FAIL: .tasks/issues/42.md not created"
  exit 1
fi

echo "--- Test 3: missing body in issues.json falls back to gh ---"
cat > "$TMPDIR/.tasks/issues.json" <<'ISSUESEOF2'
[
  {"number": 99, "title": "no body", "url": "https://x/99", "labels": [{"name": "inbox"}]}
]
ISSUESEOF2
cat > "$TMPDIR/.tasks/board.json" <<'BOARDEOF2'
[
  {"number": 99, "id": null, "title": "no body", "status": "inbox", "labels": ["inbox"], "url": "https://x/99", "assignees": [], "source": "github", "updatedAt": "", "body_sha": "", "body_preview": ""}
]
BOARDEOF2

# Create mock gh that returns body
cat > "$TMPDIR/gh" <<'MOCKEOF'
#!/usr/bin/env bash
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  echo '{"body":"fetched from GitHub"}'
  exit 0
fi
exit 1
MOCKEOF
chmod +x "$TMPDIR/gh"

CUSTOM_PATH="$TMPDIR:$PATH"
BOARD_REPO="test/repo" PATH="$CUSTOM_PATH" run_render_body --repo "test/repo" "99" >/dev/null
output=$?
if [[ $output -ne 0 ]]; then
  echo "FAIL: expected exit 0, got $output"
  exit 1
fi
echo "PASS"

echo "--- Test 4: --help flag shows usage ---"
if run_render_body --help 2>/dev/null | grep -q "Usage:"; then
  echo "PASS"
else
  echo "FAIL: --help did not show usage"
  exit 1
fi

echo "--- Test 5: missing issue number exits 1 ---"
if run_render_body 2>/dev/null; then
  echo "FAIL: expected non-zero exit for missing number"
  exit 1
fi
echo "PASS"

echo ""
echo "All board-render-body tests passed."
