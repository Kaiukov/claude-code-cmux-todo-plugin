#!/usr/bin/env bash
# Tests detached tmux spawning for headless pi workers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPAWN_BIN="$PLUGIN_ROOT/bin/orch-tmux-spawn"

if [[ ! -f "$SPAWN_BIN" ]]; then
  echo "FAIL: orch-tmux-spawn not found at $SPAWN_BIN"
  exit 1
fi

failures=0
TESTDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TESTDIR"
}
trap cleanup EXIT

make_runner_stubs() {
  mkdir -p "$TESTDIR/bin" "$TESTDIR/worktree" "$TESTDIR/repo/.tasks/orchestrator/runs"
  cat > "$TESTDIR/bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
log="${TMUX_LOG:?}"
case "${1:-}" in
  new-session)
    shift
    session=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -d) shift ;;
        -s) session="$2"; shift 2 ;;
        *) break ;;
      esac
    done
    printf 'SESSION=%s\nCMD=%s\n' "$session" "$1" >> "$log"
    bash -lc "$1"
    ;;
  list-sessions)
    printf '%s\n' "${TMUX_LIST_SESSIONS:-}"
    ;;
  *)
    echo "unsupported tmux mock call: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$TESTDIR/bin/tmux"

  cat > "$TESTDIR/bin/worker-spawn-stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${WORKER_SPAWN_ARGS_LOG:?}"
wt="$1"
mkdir -p "$wt"
printf 'done\n' > "$wt/out.json"
printf '4242\n'
EOF
  chmod +x "$TESTDIR/bin/worker-spawn-stub"

  cat > "$TESTDIR/bin/worker-watch-stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${WORKER_WATCH_ARGS_LOG:?}"
printf 'STATUS=DONE\n'
EOF
  chmod +x "$TESTDIR/bin/worker-watch-stub"

  git -C "$TESTDIR/repo" init -q
  (
    cd "$TESTDIR/repo"
    mkdir -p tracked
    echo "seed" > tracked/README.md
    git add .
    git commit -qm "init"
  )
  git -C "$TESTDIR/repo" worktree add -q -b feat/test "$TESTDIR/worktree" HEAD
}

echo "=== Test 1: raw model + high thinking spawns tmux session and writes run record ==="
make_runner_stubs
TMUX_LOG="$TESTDIR/tmux.log"
WORKER_SPAWN_ARGS_LOG="$TESTDIR/spawn.args"
WORKER_WATCH_ARGS_LOG="$TESTDIR/watch.args"
PATH="$TESTDIR/bin:$PATH"
export TMUX_LOG WORKER_SPAWN_ARGS_LOG WORKER_WATCH_ARGS_LOG
export TMUX_BIN="$TESTDIR/bin/tmux"
export ORCH_WORKER_SPAWN_BIN="$TESTDIR/bin/worker-spawn-stub"
export ORCH_WORKER_WATCH_BIN="$TESTDIR/bin/worker-watch-stub"

output="$(
  cd "$TESTDIR/repo"
  "$SPAWN_BIN" \
    --issue 151 \
    --worktree "$TESTDIR/worktree" \
    --role backend \
    --model openai-codex/gpt-5.4-mini \
    --thinking high \
    --task "codex worker"
)"

run_file="$(printf '%s\n' "$output" | awk -F= '/^run_file=/{print $2}')"
session="$(printf '%s\n' "$output" | awk -F= '/^session=/{print $2}')"
json="$(cat "$run_file")"
status="$(jq -r '.status' <<<"$json")"
model="$(jq -r '.model' <<<"$json")"
thinking="$(jq -r '.profile.thinking' <<<"$json")"
pid="$(jq -r '.pid' <<<"$json")"
if [[ "$session" == "orch-151-backend" && "$status" == "done" && "$model" == "openai-codex/gpt-5.4-mini" && "$thinking" == "high" && "$pid" == "4242" ]]; then
  echo "PASS"
else
  echo "FAIL: session=$session status=$status model=$model thinking=$thinking pid=$pid"
  failures=$((failures + 1))
fi
run_id="$(jq -r '.run_id' <<<"$json")"
tmux_session="$(jq -r '.tmux_session' <<<"$json")"
worktree_path="$(jq -r '.worktree_path' <<<"$json")"
if [[ "$run_id" == "151-backend-"* && "$tmux_session" == "orch-151-backend" && "$worktree_path" == "$TESTDIR/worktree" ]]; then
  echo "PASS: naming contract"
else
  echo "FAIL: run_id=$run_id tmux_session=$tmux_session worktree_path=$worktree_path"
  failures=$((failures + 1))
fi
if grep -q -- "openai-codex/gpt-5.4-mini" "$TESTDIR/spawn.args" && grep -q -- "--thinking high" "$TESTDIR/spawn.args"; then
  echo "PASS: worker-spawn args"
else
  echo "FAIL: worker-spawn args"
  failures=$((failures + 1))
fi

rm -rf "$TESTDIR"
TESTDIR="$(mktemp -d)"

echo "=== Test 2: profile override upgrades backend-fast low -> high ==="
make_runner_stubs
TMUX_LOG="$TESTDIR/tmux.log"
WORKER_SPAWN_ARGS_LOG="$TESTDIR/spawn.args"
WORKER_WATCH_ARGS_LOG="$TESTDIR/watch.args"
PATH="$TESTDIR/bin:$PATH"
export TMUX_LOG WORKER_SPAWN_ARGS_LOG WORKER_WATCH_ARGS_LOG
export TMUX_BIN="$TESTDIR/bin/tmux"
export ORCH_WORKER_SPAWN_BIN="$TESTDIR/bin/worker-spawn-stub"
export ORCH_WORKER_WATCH_BIN="$TESTDIR/bin/worker-watch-stub"

output="$(
  cd "$TESTDIR/repo"
  "$SPAWN_BIN" \
    --issue 152 \
    --worktree "$TESTDIR/worktree" \
    --profile backend-fast \
    --thinking high \
    --task "flash worker"
)"
run_file="$(printf '%s\n' "$output" | awk -F= '/^run_file=/{print $2}')"
json="$(cat "$run_file")"
model="$(jq -r '.model' <<<"$json")"
thinking="$(jq -r '.profile.thinking' <<<"$json")"
status="$(jq -r '.status' <<<"$json")"
log_file="$(jq -r '.log_file' <<<"$json")"
if [[ "$model" == "opencode/deepseek-v4-flash-free" && "$thinking" == "high" && "$status" == "done" && "$log_file" == *"/.tasks/orchestrator/logs/152-backend-"*".log" ]]; then
  echo "PASS"
else
  echo "FAIL: model=$model thinking=$thinking status=$status log_file=$log_file"
  failures=$((failures + 1))
fi
if grep -q -- "--profile backend-fast" "$TESTDIR/spawn.args" && grep -q -- "--thinking high" "$TESTDIR/spawn.args"; then
  echo "PASS: profile spawn args"
else
  echo "FAIL: profile spawn args"
  failures=$((failures + 1))
fi

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All orch tmux spawn tests passed."
else
  echo "$failures test(s) failed."
  exit 1
fi
