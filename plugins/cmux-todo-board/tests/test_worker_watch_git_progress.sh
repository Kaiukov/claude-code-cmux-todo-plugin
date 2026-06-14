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

failures=0
BASE_HEAD="$(git -C "$WT" rev-parse HEAD)"

case_a_out="$TMPDIR/case-a.watch"
case_b_out="$TMPDIR/case-b.watch"

echo "=== Case A: DONE after git progress ==="
printf 'done\n' > "$WT/out.json"
sleep 2 & pid_a=$!
"$WATCH" --pid "$pid_a" --out "$WT/out.json" --worktree "$WT" --stall 60 --interval 1 --max 120 >"$case_a_out" 2>&1 &
watch_pid_a=$!
sleep 0.3
git -C "$WT" commit --allow-empty --quiet -m "case-a"
HEAD_AFTER_A="$(git -C "$WT" rev-parse HEAD)"
if wait "$pid_a" 2>/dev/null; then :; fi
if wait "$watch_pid_a" 2>/dev/null; then
  watch_rc_a=0
else
  watch_rc_a=$?
fi
watch_out_a="$(cat "$case_a_out")"
if [[ "$watch_rc_a" -eq 0 ]] && [[ "$HEAD_AFTER_A" != "$BASE_HEAD" ]] && grep -q 'STATUS=DONE' <<<"$watch_out_a"; then
  echo "PASS"
else
  echo "FAIL"
  failures=$((failures + 1))
fi

echo "=== Case B: CRASHED without git progress ==="
printf 'crash\n' > "$WT/out.json"
sleep 1 & pid_b=$!
"$WATCH" --pid "$pid_b" --out "$WT/out.json" --worktree "$WT" --stall 60 --interval 1 --max 120 >"$case_b_out" 2>&1 &
watch_pid_b=$!
if wait "$pid_b" 2>/dev/null; then :; fi
if wait "$watch_pid_b" 2>/dev/null; then
  watch_rc_b=0
else
  watch_rc_b=$?
fi
HEAD_AFTER_B="$(git -C "$WT" rev-parse HEAD)"
watch_out_b="$(cat "$case_b_out")"
if [[ "$watch_rc_b" -ne 0 ]] && [[ "$HEAD_AFTER_B" == "$HEAD_AFTER_A" ]] && grep -q 'STATUS=CRASHED' <<<"$watch_out_b"; then
  echo "PASS"
else
  echo "FAIL"
  failures=$((failures + 1))
fi

if [[ "$failures" -eq 0 ]]; then
  exit 0
fi
exit 1
