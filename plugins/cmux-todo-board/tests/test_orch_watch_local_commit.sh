#!/usr/bin/env bash
# test_orch_watch_local_commit.sh — real git worktree commit should move state to "progressed".
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

WORKTREE="$TMPDIR/worktree"
mkdir -p "$WORKTREE"
git -C "$WORKTREE" init -b main 2>/dev/null
git -C "$WORKTREE" config user.email "test@test"
git -C "$WORKTREE" config user.name "Test"
echo "initial" > "$WORKTREE/file.txt"
git -C "$WORKTREE" add -A
git -C "$WORKTREE" commit -m "initial commit" 2>/dev/null

INITIAL_HEAD="$(git -C "$WORKTREE" rev-parse HEAD)"
echo "initial HEAD: ${INITIAL_HEAD:0:8}"

sleep 120 &
WORKER_PID=$!
echo "worker PID: $WORKER_PID"

RUN_ID="test-local-commit-$$"
ORCH_RUNS="$TMPDIR/.tasks/orchestrator/runs"
mkdir -p "$ORCH_RUNS"
STATE_FILE="$ORCH_RUNS/$RUN_ID.json"
STARTED="$(date +%s)"

jq -cn \
  --arg run_id "$RUN_ID" \
  --argjson issue_number 153 \
  --arg role "backend" \
  --arg worktree_path "$WORKTREE" \
  --arg branch_name "issue-153-backend" \
  --arg tmux_session "orch-153-backend" \
  --argjson pid "$WORKER_PID" \
  --argjson started "$STARTED" \
  --arg last_seen_head "$INITIAL_HEAD" \
  --argjson last_seen_remote_ref null \
  --arg state "running" \
  --arg status "running" \
  --argjson profile '{"role":"backend"}' \
  '{run_id:$run_id,issue_number:$issue_number,role:$role,worktree_path:$worktree_path,branch_name:$branch_name,tmux_session:$tmux_session,pid:$pid,started:$started,last_seen_head:$last_seen_head,last_seen_remote_ref:$last_seen_remote_ref,state:$state,status:$status,profile:$profile}' > "$STATE_FILE"

(
  cd "$TMPDIR"
  exec bash "$ORCH_WATCH" \
    --run-id "$RUN_ID" \
    --poll 1 \
    --stale 99999 \
    --timeout 99999 \
    2>"$TMPDIR/watch.log"
) &
WATCH_PID=$!
echo "orch-watch PID: $WATCH_PID"

sleep 2

if [[ ! -f "$STATE_FILE" ]]; then
  echo "FAIL: state file not created"
  cat "$TMPDIR/watch.log"
  kill "$WATCH_PID" 2>/dev/null || true
  kill "$WORKER_PID" 2>/dev/null || true
  exit 1
fi

INITIAL_STATE="$(jq -r '.state' "$STATE_FILE")"
if [[ "$INITIAL_STATE" != "running" ]]; then
  echo "FAIL: initial state should be 'running', got '$INITIAL_STATE'"
  cat "$TMPDIR/watch.log"
  kill "$WATCH_PID" 2>/dev/null || true
  kill "$WORKER_PID" 2>/dev/null || true
  exit 1
fi
echo "PASS: initial state = running"

echo "new content from worker" >> "$WORKTREE/file.txt"
git -C "$WORKTREE" add -A
git -C "$WORKTREE" commit -m "feat: worker made progress" 2>/dev/null

NEW_HEAD="$(git -C "$WORKTREE" rev-parse HEAD)"
echo "new HEAD: ${NEW_HEAD:0:8} (was ${INITIAL_HEAD:0:8})"

DETECTED=false
for i in $(seq 1 10); do
  sleep 1
  CURRENT_STATE="$(jq -r '.state' "$STATE_FILE" 2>/dev/null || true)"
  CURRENT_HEAD="$(jq -r '.head // empty' "$STATE_FILE" 2>/dev/null || true)"
  if [[ "$CURRENT_STATE" == "progressed" && "$CURRENT_HEAD" == "$NEW_HEAD" ]]; then
    DETECTED=true
    break
  fi
done

if $DETECTED; then
  echo "PASS: state transitioned to 'progressed' after commit"
else
  echo "FAIL: state did not transition to 'progressed' within 10s"
  echo "  current state: $(jq -r '.state' "$STATE_FILE" 2>/dev/null || echo 'N/A')"
  cat "$TMPDIR/watch.log"
  kill "$WATCH_PID" 2>/dev/null || true
  kill "$WORKER_PID" 2>/dev/null || true
  exit 1
fi

RECORDED_HEAD="$(jq -r '.head // empty' "$STATE_FILE")"
if [[ "$RECORDED_HEAD" == "$NEW_HEAD" ]]; then
  echo "PASS: head field updated to new commit"
else
  echo "FAIL: head field not updated"
  echo "  expected: $NEW_HEAD"
  echo "  got:      $RECORDED_HEAD"
  kill "$WATCH_PID" 2>/dev/null || true
  kill "$WORKER_PID" 2>/dev/null || true
  exit 1
fi

FINAL_STATE_FILE="$(realpath "$STATE_FILE")"
if [[ "$FINAL_STATE_FILE" == "$(realpath "$STATE_FILE")" ]]; then
  echo "PASS: watcher updated the same run file"
fi

kill "$WATCH_PID" 2>/dev/null || true
kill "$WORKER_PID" 2>/dev/null || true
wait "$WATCH_PID" 2>/dev/null || true
wait "$WORKER_PID" 2>/dev/null || true

echo ""
echo "All orch-watch local commit tests passed."
