#!/usr/bin/env bash
# test_orch_watch_remote_push.sh — local bare remote should detect branch push.
# Sets up a bare remote + clone worktree, runs a worker that commits and pushes,
# and verifies orch-watch transitions to "ready-for-verify" when the remote ref appears.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCH_WATCH="$REPO_ROOT/bin/orch-watch"

if [[ ! -f "$ORCH_WATCH" ]]; then
  echo "FAIL: orch-watch not found at $ORCH_WATCH"
  exit 1
fi

TMPDIR=$(mktemp -d)
cleanup() {
  if [[ -n "${WATCH_PID:-}" ]]; then
    kill "$WATCH_PID" 2>/dev/null || true
    wait "$WATCH_PID" 2>/dev/null || true
  fi
  if [[ -n "${WORKER_PID:-}" ]]; then
    kill "$WORKER_PID" 2>/dev/null || true
    wait "$WORKER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

REMOTE_DIR="$TMPDIR/remote.git"
git init --bare "$REMOTE_DIR" 2>/dev/null

WORKTREE="$TMPDIR/worktree"
git clone "$REMOTE_DIR" "$WORKTREE" 2>/dev/null
git -C "$WORKTREE" config user.email "test@test"
git -C "$WORKTREE" config user.name "Test"

echo "initial" > "$WORKTREE/README.md"
git -C "$WORKTREE" add -A
git -C "$WORKTREE" commit -m "initial commit" 2>/dev/null
git -C "$WORKTREE" push origin main 2>/dev/null

git -C "$WORKTREE" checkout -b feat/test-push 2>/dev/null

echo "remote: $REMOTE_DIR"
echo "worktree: $WORKTREE"
echo "branch: feat/test-push"

(
  sleep 1
  echo "CTB-DONE" > "$WORKTREE/out.json"
  echo "worker content" >> "$WORKTREE/worker-output.txt"
  git -C "$WORKTREE" add -A
  git -C "$WORKTREE" commit -m "feat: worker progress" 2>/dev/null
  git -C "$WORKTREE" push origin feat/test-push 2>/dev/null
) &
WORKER_PID=$!
echo "worker PID: $WORKER_PID"

RUN_ID="test-remote-push-$$"
ORCH_RUNS="$TMPDIR/.tasks/orchestrator/runs"
mkdir -p "$ORCH_RUNS"
STATE_FILE="$ORCH_RUNS/$RUN_ID.json"
STARTED="$(date +%s)"
INITIAL_HEAD="$(git -C "$WORKTREE" rev-parse HEAD)"

jq -cn \
  --arg run_id "$RUN_ID" \
  --argjson issue_number 153 \
  --arg role "backend" \
  --arg worktree_path "$WORKTREE" \
  --arg branch_name "feat/test-push" \
  --arg tmux_session "orch-153-backend" \
  --argjson pid "$WORKER_PID" \
  --argjson started "$STARTED" \
  --arg last_seen_head "$INITIAL_HEAD" \
  --arg last_seen_remote_ref "origin/feat/test-push" \
  --arg state "running" \
  --arg status "running" \
  --argjson profile '{"role":"backend"}' \
  '{run_id:$run_id,issue_number:$issue_number,role:$role,worktree_path:$worktree_path,branch_name:$branch_name,tmux_session:$tmux_session,pid:$pid,started:$started,last_seen_head:$last_seen_head,last_seen_remote_ref:$last_seen_remote_ref,state:$state,status:$status,profile:$profile}' > "$STATE_FILE"

(
  cd "$TMPDIR"
  exec bash "$ORCH_WATCH" \
    --run-id "$RUN_ID" \
    --remote-ref origin/feat/test-push \
    --poll 1 \
    --stale 99999 \
    --timeout 30 \
    2>"$TMPDIR/watch.log"
) &
WATCH_PID=$!
echo "orch-watch PID: $WATCH_PID"

DETECTED=false
for i in $(seq 1 30); do
  sleep 1
  if [[ -f "$STATE_FILE" ]]; then
    CURRENT_STATE="$(jq -r '.state' "$STATE_FILE" 2>/dev/null || true)"
    if [[ "$CURRENT_STATE" == "ready-for-verify" ]]; then
      DETECTED=true
      break
    fi
  fi
done

wait "$WATCH_PID" 2>/dev/null || WATCH_EXIT=$?
WATCH_EXIT="${WATCH_EXIT:-0}"

if $DETECTED && [[ "$WATCH_EXIT" -eq 0 ]]; then
  echo "PASS: state transitioned to 'ready-for-verify' after push"
else
  echo "FAIL: state did not transition to 'ready-for-verify'"
  echo "  current state: $(jq -r '.state' "$STATE_FILE" 2>/dev/null || echo 'N/A')"
  echo "--- watch log ---"
  cat "$TMPDIR/watch.log" 2>/dev/null || true
  echo "--- worker log (if any) ---"
  cat "$TMPDIR/worker.log" 2>/dev/null || true
  kill "$WORKER_PID" 2>/dev/null || true
  exit 1
fi

FINAL_STATE="$(jq -r '.state' "$STATE_FILE")"
FINAL_HEAD="$(jq -r '.head // empty' "$STATE_FILE")"
if [[ "$FINAL_STATE" == "ready-for-verify" && -n "$FINAL_HEAD" ]]; then
  echo "PASS: final state recorded in run file"
else
  echo "FAIL: final run file state invalid"
  jq '.' "$STATE_FILE"
  kill "$WORKER_PID" 2>/dev/null || true
  exit 1
fi

wait "$WORKER_PID" 2>/dev/null || true

echo ""
echo "All orch-watch remote push tests passed."
