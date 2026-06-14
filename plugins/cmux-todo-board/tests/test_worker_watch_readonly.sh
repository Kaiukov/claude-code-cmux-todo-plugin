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

# READ-ONLY DONE
printf 'done\n' > "$WT/out.json"
sleep 1 & pid_done=$!
watch_done="$TMPDIR/read-only-done.watch"
set +e
"$WATCH" --pid "$pid_done" --out "$WT/out.json" --worktree "$WT" --read-only --stall 60 --interval 1 --max 120 >"$watch_done" 2>&1
watch_rc_done=$?
set -e
wait "$pid_done" 2>/dev/null || true
watch_out_done="$(cat "$watch_done")"
if [[ "$watch_rc_done" -ne 0 ]] || ! grep -q 'STATUS=DONE' <<<"$watch_out_done"; then
  echo "FAIL: read-only done"
  exit 1
fi

# READ-ONLY FAIL
: > "$WT/out.json"
sleep 1 & pid_fail=$!
watch_fail="$TMPDIR/read-only-fail.watch"
set +e
"$WATCH" --pid "$pid_fail" --out "$WT/out.json" --worktree "$WT" --read-only --stall 60 --interval 1 --max 120 >"$watch_fail" 2>&1
watch_rc_fail=$?
set -e
wait "$pid_fail" 2>/dev/null || true
watch_out_fail="$(cat "$watch_fail")"
if [[ "$watch_rc_fail" -eq 0 ]] || ! grep -q 'STATUS=CRASHED' <<<"$watch_out_fail"; then
  echo "FAIL: read-only empty out should crash"
  exit 1
fi

# WRITE MODE CRASHED
printf 'write\n' > "$WT/out.json"
sleep 1 & pid_write_crash=$!
watch_write_crash="$TMPDIR/write-crash.watch"
set +e
"$WATCH" --pid "$pid_write_crash" --out "$WT/out.json" --worktree "$WT" --stall 60 --interval 1 --max 120 >"$watch_write_crash" 2>&1
watch_rc_write_crash=$?
set -e
wait "$pid_write_crash" 2>/dev/null || true
watch_out_write_crash="$(cat "$watch_write_crash")"
if [[ "$watch_rc_write_crash" -eq 0 ]] || ! grep -q 'STATUS=CRASHED' <<<"$watch_out_write_crash"; then
  echo "FAIL: write mode without commit should crash"
  exit 1
fi

# WRITE MODE DONE
printf 'write\n' > "$WT/out.json"
sleep 2 & pid_write_done=$!
watch_write_done="$TMPDIR/write-done.watch"
set +e
"$WATCH" --pid "$pid_write_done" --out "$WT/out.json" --worktree "$WT" --stall 60 --interval 1 --max 120 >"$watch_write_done" 2>&1 &
watch_pid_write_done=$!
sleep 0.3
git -C "$WT" commit --allow-empty --quiet -m "watch-write-done"
wait "$watch_pid_write_done"
watch_rc_write_done=$?
set -e
wait "$pid_write_done" 2>/dev/null || true
watch_out_write_done="$(cat "$watch_write_done")"
if [[ "$watch_rc_write_done" -ne 0 ]] || ! grep -q 'STATUS=DONE' <<<"$watch_out_write_done"; then
  echo "FAIL: write mode with commit should done"
  exit 1
fi

exit 0
