#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WATCH="$REPO_ROOT/skills/cmux-agent-workflows/scripts/worker-watch.sh"

if [[ ! -x "$WATCH" ]]; then
  echo "FAIL: worker-watch.sh not found or not executable at $WATCH"
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

ROOT="$TMPDIR/repo"
WT="$TMPDIR/wt"
mkdir -p "$ROOT"

git -C "$ROOT" init --quiet
git -C "$ROOT" config user.email "test@test.test"
git -C "$ROOT" config user.name "Test"
: > "$ROOT/base.txt"
git -C "$ROOT" add base.txt
git -C "$ROOT" commit --quiet -m "init"
git -C "$ROOT" worktree add --quiet -b feature "$WT" HEAD

slug="${WT//\//-}"
SESSION_ROOT="$TMPDIR/home/.pi/agent/sessions"
PRIMARY_DIR="$SESSION_ROOT/-${slug}--"
mkdir -p "$PRIMARY_DIR"

echo "old" > "$PRIMARY_DIR/old.jsonl"
touch -t 200001010000 "$PRIMARY_DIR/old.jsonl"

printf 'stale\n' > "$WT/out.json"
sleep 2 & pid_a=$!
watch_a="$TMPDIR/stale.watch"
set +e
HOME="$TMPDIR/home" "$WATCH" --pid "$pid_a" --out "$WT/out.json" --worktree "$WT" --stall 2 --interval 1 --max 30 >"$watch_a" 2>&1
watch_rc_a=$?
set -e
wait "$pid_a" 2>/dev/null || true
watch_out_a="$(cat "$watch_a")"
if [[ "$watch_rc_a" -eq 1 ]] && ! grep -q 'STATUS=KILLED_STALLED' <<<"$watch_out_a"; then
  :
else
  echo "FAIL: stale heartbeat killed at t+0"
  exit 1
fi

rm -rf "$SESSION_ROOT"
mkdir -p "$SESSION_ROOT"

sleep 10 & pid_b=$!
watch_b="$TMPDIR/stall.watch"
set +e
HOME="$TMPDIR/home" "$WATCH" --pid "$pid_b" --out "$WT/out.json" --worktree "$WT" --stall 2 --interval 1 --max 30 >"$watch_b" 2>&1 &
watch_pid_b=$!
sleep 1
mkdir -p "$PRIMARY_DIR"
: > "$PRIMARY_DIR/live.jsonl"
wait "$watch_pid_b"
watch_rc_b=$?
set -e
wait "$pid_b" 2>/dev/null || true
watch_out_b="$(cat "$watch_b")"
if [[ "$watch_rc_b" -eq 125 ]] && grep -q 'STATUS=KILLED_STALLED' <<<"$watch_out_b"; then
  exit 0
fi

echo "FAIL: genuine stall was not killed"
exit 1
