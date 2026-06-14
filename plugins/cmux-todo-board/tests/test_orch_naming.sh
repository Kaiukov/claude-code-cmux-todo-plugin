#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPAWN_BIN="$PLUGIN_ROOT/bin/orch-spawn"

if [[ ! -x "$SPAWN_BIN" ]]; then
  echo "FAIL: orch-spawn not found at $SPAWN_BIN"
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

STUB="$TMPDIR/orch-tmux-spawn-stub"
cat >"$STUB" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "${ORCH_SPAWN_LOG:?}"
EOF
chmod +x "$STUB"

failures=0

run_case() {
  local label="$1" role="$2" task_id="$3" issue="$4" session="$5" worktree_base="$6"
  local log="$TMPDIR/$label.args"

  if ! ORCH_SPAWN_LOG="$log" ORCH_TMUX_SPAWN="$STUB" "$SPAWN_BIN" --role "$role" --task-id "$task_id"; then
    echo "FAIL: $label spawn failed"
    failures=$((failures + 1))
    return
  fi

  args=()
  while IFS= read -r line; do
    args+=("$line")
  done < "$log"
  if [[ ${#args[@]} -ne 10 ]]; then
    echo "FAIL: $label argv=${args[*]-}"
    failures=$((failures + 1))
    return
  fi

  if [[ "${args[0]}" == "--issue" && "${args[1]}" == "$issue" && "${args[2]}" == "--worktree" && "$(basename "${args[3]}")" == "$worktree_base" && "${args[4]}" == "--profile" && "${args[5]}" == "$role" && "${args[6]}" == "--role" && "${args[7]}" == "$role" && "${args[8]}" == "--session" && "${args[9]}" == "$session" ]]; then
    echo "PASS: $label"
  else
    echo "FAIL: $label argv=${args[*]}"
    failures=$((failures + 1))
  fi
}

run_case backend-142 backend 142 142 orch-142-backend wt-issue-142-backend
run_case backend-0142 backend 0142 142 orch-142-backend wt-issue-142-backend
run_case reviewer-7 reviewer 7 7 orch-7-reviewer wt-issue-7-reviewer

if [[ $failures -eq 0 ]]; then
  exit 0
fi

exit 1
