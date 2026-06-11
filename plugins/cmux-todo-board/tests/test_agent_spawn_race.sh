#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPAWN_SCRIPT="$REPO_ROOT/skills/cmux-agent-workflows/scripts/agent-spawn.sh"

if [[ ! -f "$SPAWN_SCRIPT" ]]; then
  echo "FAIL: agent-spawn.sh not found at $SPAWN_SCRIPT"
  exit 1
fi

# --- Setup mock environment ---
MOCK_DIR=$(mktemp -d)
WT1=$(mktemp -d)
WT2=$(mktemp -d)
SEND_LOG=$(mktemp)
CNT_FILE=$(mktemp)
echo "0" > "$CNT_FILE"

cleanup() { rm -rf "$MOCK_DIR" "$WT1" "$WT2" "$SEND_LOG" "$CNT_FILE"; }
trap cleanup EXIT

# Mock cmux binary: atomically increments surface counter via mkdir mutex.
cat > "$MOCK_DIR/cmux" << 'SCRIPT_EOF'
#!/usr/bin/env bash
CNT_FILE="${CMUX_CNT_FILE:-/dev/null}"
SEND_LOG="${CMUX_SEND_LOG:-/dev/null}"
case "$1" in
  tree) echo '[]' ;;
  new-split)
    LOCK_DIR="${CNT_FILE}.lock"
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do :; done
    cnt=$(cat "$CNT_FILE")
    cnt=$((cnt + 1))
    echo "$cnt" > "$CNT_FILE"
    rmdir "$LOCK_DIR"
    echo "OK surface:$cnt workspace:$((cnt * 10))"
    ;;
  rename-tab) exit 0 ;;
  send)
    found=0
    for a in "$@"; do
      if [[ $found -eq 1 ]]; then printf '%s\n' "$a"; fi
      if [[ "$a" == "--" ]]; then found=1; fi
    done >> "$SEND_LOG"
    exit 0
    ;;
  send-key) exit 0 ;;
  read-screen) echo "OpenAI Codex gpt-5-codex medium · /path" ;;
  *) exit 0 ;;
esac
SCRIPT_EOF
chmod +x "$MOCK_DIR/cmux"

# Mock codex binary (only checked via `command -v`).
cat > "$MOCK_DIR/codex" << 'SCRIPT_EOF'
#!/usr/bin/env bash
exit 0
SCRIPT_EOF
chmod +x "$MOCK_DIR/codex"

export PATH="$MOCK_DIR:$PATH"
export CMUX_CNT_FILE="$CNT_FILE"
export CMUX_SEND_LOG="$SEND_LOG"

failures=0

echo "=== Test 1: concurrent spawns get distinct surface refs ==="

OUT1=$(mktemp) OUT2=$(mktemp)
"$SPAWN_SCRIPT" right "$WT1" codex t1 --agent codex --quiet > "$OUT1" 2>/dev/null &
PID1=$!
"$SPAWN_SCRIPT" right "$WT2" codex t2 --agent codex --quiet > "$OUT2" 2>/dev/null &
PID2=$!

wait $PID1; RC1=$?
wait $PID2; RC2=$?

if [[ $RC1 -ne 0 ]]; then echo "FAIL: spawn 1 exited $RC1"; failures=$((failures + 1)); fi
if [[ $RC2 -ne 0 ]]; then echo "FAIL: spawn 2 exited $RC2"; failures=$((failures + 1)); fi

SURF1=$(cat "$OUT1")
SURF2=$(cat "$OUT2")

if [[ "$SURF1" != "$SURF2" ]] && [[ -n "$SURF1" ]] && [[ -n "$SURF2" ]]; then
  echo "PASS: distinct surfaces ($SURF1, $SURF2)"
else
  echo "FAIL: surfaces '$SURF1' vs '$SURF2'"
  failures=$((failures + 1))
fi

echo "=== Test 2: each surface got its own worktree path (no cross-contamination) ==="

# The send log should contain exactly one line per spawn, each with its own WT.
SURF1_WT_HITS=$(grep -c "$WT1" "$SEND_LOG" 2>/dev/null || true)
SURF2_WT_HITS=$(grep -c "$WT2" "$SEND_LOG" 2>/dev/null || true)

if [[ "$SURF1_WT_HITS" == "1" ]] && [[ "$SURF2_WT_HITS" == "1" ]]; then
  echo "PASS: each spawn sent its own worktree path exactly once"
else
  echo "FAIL: WT1 hits=$SURF1_WT_HITS WT2 hits=$SURF2_WT_HITS (expected 1 each)"
  failures=$((failures + 1))
fi

echo "=== Test 3: surface refs match surface:NN pattern ==="

if echo "$SURF1" | grep -qE '^surface:[0-9]+$' && echo "$SURF2" | grep -qE '^surface:[0-9]+$'; then
  echo "PASS: both surfaces match surface:NN"
else
  echo "FAIL: bad surface format ($SURF1, $SURF2)"
  failures=$((failures + 1))
fi

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All agent-spawn race tests passed."
else
  echo "${failures} test(s) failed."
  exit 1
fi
