#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_JSON="$SCRIPT_DIR/../hooks/hooks.json"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ ! -f "$HOOKS_JSON" ]]; then
  echo "FAIL: hooks.json not found at $HOOKS_JSON"
  exit 1
fi

# Extract the SessionStart hook command from hooks.json
HOOK_CMD="$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$HOOKS_JSON")"
if [[ -z "$HOOK_CMD" || "$HOOK_CMD" == "null" ]]; then
  echo "FAIL: could not extract hook command from hooks.json"
  exit 1
fi

# Helper: run the hook command in a given working directory with optional env
run_hook() {
  local workdir="$1"
  shift
  env -i HOME="$HOME" PATH="$PATH" CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}" "$@" \
    bash -c "cd '$workdir' && $HOOK_CMD" 2>&1; local rc=$?
  # Separate stdout / stderr
  # Actually, we need stdout and stderr separately. Let's use a different approach.
  return $rc
}

# Better helper: capture stdout and stderr separately
run_hook_capture() {
  local workdir="$1"
  shift
  local out_file out_code err_file
  out_file="$(mktemp)"
  err_file="$(mktemp)"
  env -i HOME="$HOME" PATH="$PATH" CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}" "$@" \
    bash -c "cd '$workdir' && $HOOK_CMD" >"$out_file" 2>"$err_file"; local rc=$?
  echo "__STDOUT__"
  cat "$out_file"
  echo "__STDERR__"
  cat "$err_file"
  echo "__EXIT__$rc"
  rm -f "$out_file" "$err_file"
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "=== test_sessionstart_hook.sh ==="

# -------------------------------------------------------------------
echo "--- Test 1: hook command resolves binary when CLAUDE_PLUGIN_ROOT is set ---"
mkdir -p "$TMPDIR/plugin-root/bin"
# Create a mock board-status that echoes a known line
cat > "$TMPDIR/plugin-root/bin/board-status" <<'MOCK'
#!/usr/bin/env bash
echo "inbox=0 ready=0 in-progress=0 needs-review=0 blocked=0 needs-info=0 done=0"
MOCK
chmod +x "$TMPDIR/plugin-root/bin/board-status"

mkdir -p "$TMPDIR/test1/.tasks"
echo '[]' > "$TMPDIR/test1/.tasks/board.json"

export CLAUDE_PLUGIN_ROOT="$TMPDIR/plugin-root"
result="$(run_hook_capture "$TMPDIR/test1")"
unset CLAUDE_PLUGIN_ROOT

exit_code="$(echo "$result" | grep '__EXIT__' | sed 's/__EXIT__//')"
stdout="$(echo "$result" | sed -n '/__STDOUT__/,/__STDERR__/p' | sed '1d;/__STDERR__/,$d')"
# stderr for reference
stderr="$(echo "$result" | sed -n '/__STDERR__/,$p' | sed '1d')"

if [[ "$exit_code" != "0" ]]; then
  echo "FAIL: expected exit 0, got $exit_code"
  echo "stdout: $stdout"
  echo "stderr: $stderr"
  exit 1
fi

if echo "$stdout" | grep -q "inbox=0"; then
  echo "PASS"
else
  echo "FAIL: expected 'inbox=0' in output, got: $stdout"
  exit 1
fi

# -------------------------------------------------------------------
echo "--- Test 2: hook produces at most 3 lines of stdout ---"
mkdir -p "$TMPDIR/test2/.tasks"
cat > "$TMPDIR/test2/.tasks/board.json" <<'BOARDEOF'
[
  {"number": 1, "id": null, "title": "task one", "status": "ready", "labels": ["ready"], "url": "", "assignees": [], "source": "local"},
  {"number": 2, "id": null, "title": "task two", "status": "inbox", "labels": ["inbox"], "url": "", "assignees": [], "source": "local"}
]
BOARDEOF

export CLAUDE_PLUGIN_ROOT="$TMPDIR/plugin-root"
result="$(run_hook_capture "$TMPDIR/test2")"
unset CLAUDE_PLUGIN_ROOT

exit_code="$(echo "$result" | grep '__EXIT__' | sed 's/__EXIT__//')"
stdout="$(echo "$result" | sed -n '/__STDOUT__/,/__STDERR__/p' | sed '1d;/__STDERR__/,$d')"

if [[ "$exit_code" != "0" ]]; then
  echo "FAIL: expected exit 0, got $exit_code"
  exit 1
fi

line_count="$(echo "$stdout" | grep -c . || true)"
if [[ "$line_count" -le 3 ]]; then
  echo "PASS (lines=$line_count)"
else
  echo "FAIL: expected ≤3 stdout lines, got $line_count"
  echo "stdout: $stdout"
  exit 1
fi

# -------------------------------------------------------------------
echo "--- Test 3: hook exits 0 and emits no stdout when .tasks/board.json is absent ---"
mkdir -p "$TMPDIR/test3"
# No .tasks/board.json

export CLAUDE_PLUGIN_ROOT="$TMPDIR/plugin-root"
result="$(run_hook_capture "$TMPDIR/test3")"
unset CLAUDE_PLUGIN_ROOT

exit_code="$(echo "$result" | grep '__EXIT__' | sed 's/__EXIT__//')"
stdout="$(echo "$result" | sed -n '/__STDOUT__/,/__STDERR__/p' | sed '1d;/__STDERR__/,$d')"

if [[ "$exit_code" != "0" ]]; then
  echo "FAIL: expected exit 0, got $exit_code"
  exit 1
fi

if [[ -z "$stdout" ]]; then
  echo "PASS"
else
  echo "FAIL: expected no stdout, got: $stdout"
  exit 1
fi

# -------------------------------------------------------------------
echo "--- Test 4: hook does not contain a bare repo-relative bin/board-status ---"
if echo "$HOOK_CMD" | grep -q 'bin/board-status' && ! echo "$HOOK_CMD" | grep -q 'CLAUDE_PLUGIN_ROOT'; then
  echo "FAIL: hook contains bare repo-relative bin/board-status without CLAUDE_PLUGIN_ROOT guard"
  exit 1
fi
echo "PASS"

# -------------------------------------------------------------------
echo "--- Test 5: walk-up resolution works when CLAUDE_PLUGIN_ROOT is unset ---"
mkdir -p "$TMPDIR/project/plugins/cmux-todo-board/bin"
cat > "$TMPDIR/project/plugins/cmux-todo-board/bin/board-status" <<'MOCK2'
#!/usr/bin/env bash
echo "inbox=5 ready=3 done=10"
MOCK2
chmod +x "$TMPDIR/project/plugins/cmux-todo-board/bin/board-status"
mkdir -p "$TMPDIR/project/.tasks"
echo '[]' > "$TMPDIR/project/.tasks/board.json"

result="$(run_hook_capture "$TMPDIR/project")"
exit_code="$(echo "$result" | grep '__EXIT__' | sed 's/__EXIT__//')"
stdout="$(echo "$result" | sed -n '/__STDOUT__/,/__STDERR__/p' | sed '1d;/__STDERR__/,$d')"

if [[ "$exit_code" != "0" ]]; then
  echo "FAIL: expected exit 0, got $exit_code"
  echo "stdout: $stdout"
  exit 1
fi

if echo "$stdout" | grep -q "inbox=5"; then
  echo "PASS"
else
  echo "FAIL: expected 'inbox=5' in output, got: $stdout"
  exit 1
fi

# -------------------------------------------------------------------
echo "--- Test 6: hook exits 0 silently when binary not found ---"
mkdir -p "$TMPDIR/test6"
# No board-status binary anywhere

result="$(run_hook_capture "$TMPDIR/test6")"
exit_code="$(echo "$result" | grep '__EXIT__' | sed 's/__EXIT__//')"
stdout="$(echo "$result" | sed -n '/__STDOUT__/,/__STDERR__/p' | sed '1d;/__STDERR__/,$d')"
stderr="$(echo "$result" | sed -n '/__STDERR__/,$p' | sed '1d')"

if [[ "$exit_code" != "0" ]]; then
  echo "FAIL: expected exit 0, got $exit_code"
  exit 1
fi

if [[ -z "$stdout" ]]; then
  echo "PASS"
else
  echo "FAIL: expected no stdout when binary not found, got: $stdout"
  exit 1
fi

echo ""
echo "All sessionstart hook tests passed."
