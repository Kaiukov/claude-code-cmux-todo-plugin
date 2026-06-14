#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
DISPATCH_BIN="$PLUGIN_ROOT/bin/orch-dispatch"

if [[ ! -x "$DISPATCH_BIN" ]]; then
  echo "FAIL: orch-dispatch not found at $DISPATCH_BIN"
  exit 1
fi

TMPDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/.tasks/orchestrator/runs"

cat > "$TMPDIR/bin/orch-spawn" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${ORCH_SPAWN_ARGS_LOG:?}"
printf 'run_file=%s\n' "${ORCH_RUN_FILE:?}"
printf 'session=%s\n' "${ORCH_SESSION:?}"
EOF
chmod +x "$TMPDIR/bin/orch-spawn"

cat > "$TMPDIR/bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${TMUX_LOG:?}"
echo "FAIL: unexpected tmux invocation" >&2
exit 1
EOF
chmod +x "$TMPDIR/bin/tmux"

export ORCH_SPAWN="$TMPDIR/bin/orch-spawn"
export ORCH_SPAWN_ARGS_LOG="$TMPDIR/orch-spawn.args"
export ORCH_RUN_FILE="$TMPDIR/.tasks/orchestrator/runs/153-backend-FAKE.json"
export ORCH_SESSION="orch-153-backend"
export TMUX_LOG="$TMPDIR/tmux.log"
PATH="$TMPDIR/bin:$PATH"
export PATH

before_worktrees="$(git -C "$REPO_ROOT" worktree list --porcelain | awk '/^worktree / {print $2}' | grep '/wt-issue-' || true)"

output="$($DISPATCH_BIN --task-id 153 --role backend)"

expected_args="--role backend --task-id 153"
actual_args="$(cat "$ORCH_SPAWN_ARGS_LOG")"
if [[ "$actual_args" == "$expected_args" ]]; then
  echo "PASS: orch-spawn args"
else
  echo "FAIL: orch-spawn args: $actual_args"
  exit 1
fi

if [[ "$output" == *"run_id=153-backend-FAKE"* && "$output" == *"session=orch-153-backend"* ]]; then
  echo "PASS: summary output"
else
  echo "FAIL: output: $output"
  exit 1
fi

if [[ ! -e "$TMUX_LOG" ]]; then
  echo "PASS: no tmux invocation"
else
  echo "FAIL: tmux was invoked"
  exit 1
fi

after_worktrees="$(git -C "$REPO_ROOT" worktree list --porcelain | awk '/^worktree / {print $2}' | grep '/wt-issue-' || true)"
if [[ "$before_worktrees" == "$after_worktrees" ]]; then
  echo "PASS: no real wt-issue worktree created"
else
  echo "FAIL: worktree list changed"
  printf 'before:\n%s\n' "$before_worktrees"
  printf 'after:\n%s\n' "$after_worktrees"
  exit 1
fi

echo "All orch-dispatch tests passed."
