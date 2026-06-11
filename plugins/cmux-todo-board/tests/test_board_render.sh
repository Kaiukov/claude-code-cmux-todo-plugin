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

echo "--- Test 9: local.json entries appear in board.json with source:local ---"
cat > "$TMPDIR/.tasks/local.json" <<'LOCALEOF'
[
  {"id": "L1", "title": "deploy to dev", "status": "ready", "created": "2025-01-01T00:00:00Z"},
  {"id": "L2", "title": "check logs", "status": "blocked", "created": "2025-01-02T00:00:00Z"}
]
LOCALEOF
run_render 2>/dev/null
local_sources=$(python3 -c "import json; data=json.load(open('$TMPDIR/.tasks/board.json')); print(' '.join(t['source'] for t in data if t.get('source')=='local'))")
local_ids=$(python3 -c "import json; data=json.load(open('$TMPDIR/.tasks/board.json')); print(' '.join(str(t['id']) for t in data if t.get('source')=='local'))")
if [[ "$local_sources" == "local local" && "$local_ids" == "L1 L2" ]]; then
  echo "PASS"
else
  echo "FAIL: got sources='$local_sources' ids='$local_ids'"
  exit 1
fi

echo "--- Test 10: TODO.md shows [L1] for local tasks ---"
if grep -q '\[L1\]' "$TMPDIR/TODO.md" && grep -q '\[L2\]' "$TMPDIR/TODO.md"; then
  echo "PASS"
else
  echo "FAIL: TODO.md missing [L1] or [L2] local task markers"
  grep -E 'L1|L2' "$TMPDIR/TODO.md" || true
  exit 1
fi

echo "--- Test 11: local tasks sorted after github within same status ---"
# Add a local task with ready status; github issues #2 and #9 are also ready
cat > "$TMPDIR/.tasks/local.json" <<'LOCALEOF2'
[
  {"id": "L1", "title": "local ready task", "status": "ready", "created": "2025-01-01T00:00:00Z"}
]
LOCALEOF2
run_render 2>/dev/null
# Extract ready section lines from TODO.md
ready_lines=$(python3 -c "
lines = open('$TMPDIR/TODO.md').read().split('\n')
in_ready = False
for l in lines:
    if l.startswith('## ready'):
        in_ready = True
        continue
    if in_ready and l.startswith('## '):
        break
    if in_ready and l.strip():
        print(l.strip())
")
# github issues (#2, #9) should come first, then local L1 last
last_ready=$(echo "$ready_lines" | tail -1)
if echo "$last_ready" | grep -q '\[L1\]'; then
  echo "PASS"
else
  echo "FAIL: local task not last in ready section"
  echo "ready_lines:"
  echo "$ready_lines"
  exit 1
fi

echo "--- Test 12: summary includes local tasks ---"
summary=$(run_render 2>&1)
# 9 github + 1 local = 10 total; ready: #2, #9 (multi-label), L1 = 3
if echo "$summary" | grep -q "10 tasks" && echo "$summary" | grep -q "ready=3" && echo "$summary" | grep -q "blocked=1" && echo "$summary" | grep -q "in-progress=1"; then
  echo "PASS"
else
  echo "FAIL: summary line: $summary"
  exit 1
fi

echo "--- Test 13: no local.json — unchanged behaviour ---"
rm -f "$TMPDIR/.tasks/local.json"
run_render 2>/dev/null
github_count=$(python3 -c "import json; data=json.load(open('$TMPDIR/.tasks/board.json')); print(len(data))")
if [[ "$github_count" == "9" ]]; then
  echo "PASS"
else
  echo "FAIL: expected 9 github tasks, got $github_count"
  exit 1
fi

echo "--- Test 14: issue body persisted to .tasks/issues/<n>.md ---"
cat > "$TMPDIR/.tasks/issues.json" <<'BODYEOF'
[
  {
    "number": 42,
    "title": "demo",
    "labels": [{"name": "ready"}],
    "url": "https://x/42",
    "assignees": [],
    "body": "hello world"
  }
]
BODYEOF
rm -f "$TMPDIR/.tasks/local.json"
run_render 2>/dev/null
md_path="$TMPDIR/.tasks/issues/42.md"
if [[ ! -f "$md_path" ]]; then
  echo "FAIL: .tasks/issues/42.md was not created"
  exit 1
fi
if grep -q "# #42 demo" "$md_path" && grep -q "Status: ready" "$md_path" && grep -q "hello world" "$md_path"; then
  echo "PASS"
else
  echo "FAIL: .tasks/issues/42.md content wrong:"
  cat "$md_path"
  exit 1
fi

echo "--- Test 15: missing body writes '(no body)' (ready issue) ---"
cat > "$TMPDIR/.tasks/issues.json" <<'NOBODYEOF'
[
  {
    "number": 99,
    "title": "no body issue",
    "labels": [{"name": "ready"}],
    "url": "https://x/99",
    "assignees": []
  }
]
NOBODYEOF
rm -f "$TMPDIR/.tasks/local.json"
rm -f "$TMPDIR/.tasks/issues/42.md"
run_render 2>/dev/null
md_path="$TMPDIR/.tasks/issues/99.md"
if [[ ! -f "$md_path" ]]; then
  echo "FAIL: .tasks/issues/99.md was not created"
  exit 1
fi
if grep -q "# #99 no body issue" "$md_path" && grep -q "(no body)" "$md_path"; then
  echo "PASS"
else
  echo "FAIL: .tasks/issues/99.md content wrong:"
  cat "$md_path"
  exit 1
fi

echo "--- Test 16: no .md for local tasks ---"
cat > "$TMPDIR/.tasks/local.json" <<'LOCALNOMD'
[
  {"id": "L1", "title": "local only", "status": "ready"}
]
LOCALNOMD
cat > "$TMPDIR/.tasks/issues.json" <<'EMPTY'
[]
EMPTY
rm -f "$TMPDIR/.tasks/issues/99.md"
run_render 2>/dev/null
if [[ -f "$TMPDIR/.tasks/issues/L1.md" ]]; then
  echo "FAIL: .tasks/issues/L1.md should not exist for local tasks"
  exit 1
fi
local_count=$(python3 -c "import json; data=json.load(open('$TMPDIR/.tasks/board.json')); print(len([t for t in data if t.get('source')=='local']))")
if [[ "$local_count" == "1" && ! -f "$TMPDIR/.tasks/issues/L1.md" ]]; then
  echo "PASS"
else
  echo "FAIL: local task handling wrong"
  exit 1
fi

echo "--- Test 17: non-ready issue does NOT get per-issue .md file ---"
cat > "$TMPDIR/.tasks/issues.json" <<'NONREADYEOF'
[
  {
    "number": 100,
    "title": "inbox task",
    "labels": [{"name": "inbox"}],
    "url": "https://x/100",
    "assignees": [],
    "body": "full body here"
  },
  {
    "number": 101,
    "title": "blocked task",
    "labels": [{"name": "blocked"}],
    "url": "https://x/101",
    "assignees": [],
    "body": "blocked body"
  },
  {
    "number": 102,
    "title": "ready task",
    "labels": [{"name": "ready"}],
    "url": "https://x/102",
    "assignees": [],
    "body": "ready body content"
  }
]
NONREADYEOF
rm -f "$TMPDIR/.tasks/local.json"
rm -rf "$TMPDIR/.tasks/issues"
run_render 2>/dev/null
if [[ -f "$TMPDIR/.tasks/issues/100.md" ]]; then
  echo "FAIL: .tasks/issues/100.md should NOT exist for inbox"
  exit 1
fi
if [[ -f "$TMPDIR/.tasks/issues/101.md" ]]; then
  echo "FAIL: .tasks/issues/101.md should NOT exist for blocked"
  exit 1
fi
if [[ ! -f "$TMPDIR/.tasks/issues/102.md" ]]; then
  echo "FAIL: .tasks/issues/102.md should exist for ready"
  exit 1
fi
echo "PASS"

echo "--- Test 18: board.json has compact fields (updatedAt, body_sha, body_preview) ---"
# Check that all github tasks in board.json have these fields
fields_ok=$(python3 -c "
import json
data = json.load(open('$TMPDIR/.tasks/board.json'))
for t in data:
    if t.get('source') == 'github':
        if 'updatedAt' not in t:
            print('FAIL: missing updatedAt for', t['number'])
            exit(1)
        if 'body_sha' not in t:
            print('FAIL: missing body_sha for', t['number'])
            exit(1)
        if 'body_preview' not in t:
            print('FAIL: missing body_preview for', t['number'])
            exit(1)
print('OK')
")
if [[ "$fields_ok" == "OK" ]]; then
  echo "PASS"
else
  echo "FAIL: $fields_ok"
  exit 1
fi

echo "--- Test 19: body_preview is capped at 200 chars ---"
long_body="a"
for i in $(seq 1 250); do long_body="${long_body}b"; done
cat > "$TMPDIR/.tasks/issues.json" <<PREVIEWEOF
[
  {
    "number": 200,
    "title": "long body task",
    "labels": [{"name": "ready"}],
    "url": "https://x/200",
    "assignees": [],
    "body": "${long_body}"
  }
]
PREVIEWEOF
rm -f "$TMPDIR/.tasks/local.json"
rm -rf "$TMPDIR/.tasks/issues"
run_render 2>/dev/null
preview_len=$(python3 -c "import json; d=json.load(open('$TMPDIR/.tasks/board.json')); print(len(d[0]['body_preview']))")
if [[ "$preview_len" == "200" ]]; then
  echo "PASS"
else
  echo "FAIL: body_preview length is $preview_len, expected 200"
  exit 1
fi

echo "--- Test 20: body_sha is hash of body ---"
cat > "$TMPDIR/.tasks/issues.json" <<'SHAEOF'
[
  {
    "number": 300,
    "title": "hash test",
    "labels": [{"name": "inbox"}],
    "url": "https://x/300",
    "assignees": [],
    "body": "test body"
  }
]
SHAEOF
rm -f "$TMPDIR/.tasks/local.json"
rm -rf "$TMPDIR/.tasks/issues"
run_render 2>/dev/null
sha=$(python3 -c "import json, hashlib; d=json.load(open('$TMPDIR/.tasks/board.json')); print(d[0]['body_sha'])")
expected_sha=$(python3 -c "import hashlib; print(hashlib.sha256(b'test body').hexdigest())")
if [[ "$sha" == "$expected_sha" ]]; then
  echo "PASS"
else
  echo "FAIL: body_sha=$sha, expected=$expected_sha"
  exit 1
fi

echo "--- Test 21: board.json still has required fields (source, assignees, id, labels) ---"
required_ok=$(python3 -c "
import json
data = json.load(open('$TMPDIR/.tasks/board.json'))
for t in data:
    for f in ('source', 'assignees', 'id', 'labels', 'number', 'title', 'status', 'url'):
        if f not in t:
            print('FAIL: missing field', f, 'for task', t.get('number'))
            exit(1)
print('OK')
")
if [[ "$required_ok" == "OK" ]]; then
  echo "PASS"
else
  echo "FAIL: $required_ok"
  exit 1
fi

echo ""
echo "All tests passed."
