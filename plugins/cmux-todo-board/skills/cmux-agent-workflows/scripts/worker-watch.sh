#!/usr/bin/env bash
# Waiter + liveness watchdog for headless pi workers.
# Watches the worker PID plus the pi session-jsonl heartbeat mtime.
#
# Usage: worker-watch.sh --pid <PID> --out <outfile> [--worktree <dir>] \
#                        [--max <seconds=1800>] [--stall <seconds=120>] [--interval <seconds=10>]
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: worker-watch.sh --pid <PID> --out <outfile> [--worktree <dir>] [--max <seconds=1800>] [--stall <seconds=120>] [--interval <seconds=10>]
EOF
}

is_uint() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

file_mtime() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  stat -f %m "$file" 2>/dev/null
}

newest_mtime_in_dir() {
  local dir="$1" newest="" file mtime
  [[ -d "$dir" ]] || return 1
  while IFS= read -r -d '' file; do
    mtime="$(file_mtime "$file" 2>/dev/null || true)"
    [[ -n "$mtime" ]] || continue
    if [[ -z "$newest" || "$mtime" -gt "$newest" ]]; then
      newest="$mtime"
    fi
  done < <(find "$dir" -type f -name '*.jsonl' -print0 2>/dev/null)
  [[ -n "$newest" ]] || return 1
  printf '%s\n' "$newest"
}

newest_mtime_after() {
  local root="$1" since="$2" newest="" file mtime
  [[ -d "$root" ]] || return 1
  while IFS= read -r -d '' file; do
    mtime="$(file_mtime "$file" 2>/dev/null || true)"
    [[ -n "$mtime" ]] || continue
    if (( mtime >= since )) && [[ -z "$newest" || "$mtime" -gt "$newest" ]]; then
      newest="$mtime"
    fi
  done < <(find "$root" -type f -name '*.jsonl' -print0 2>/dev/null)
  [[ -n "$newest" ]] || return 1
  printf '%s\n' "$newest"
}

PID=""; OUT=""; WORKTREE=""; MAX=1800; STALL=120; INTERVAL=10
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pid) [[ $# -ge 2 ]] || { usage; exit 2; }; PID="$2"; shift 2 ;;
    --pid=*) PID="${1#--pid=}"; shift ;;
    --out) [[ $# -ge 2 ]] || { usage; exit 2; }; OUT="$2"; shift 2 ;;
    --out=*) OUT="${1#--out=}"; shift ;;
    --worktree) [[ $# -ge 2 ]] || { usage; exit 2; }; WORKTREE="$2"; shift 2 ;;
    --worktree=*) WORKTREE="${1#--worktree=}"; shift ;;
    --max) [[ $# -ge 2 ]] || { usage; exit 2; }; MAX="$2"; shift 2 ;;
    --max=*) MAX="${1#--max=}"; shift ;;
    --stall) [[ $# -ge 2 ]] || { usage; exit 2; }; STALL="$2"; shift 2 ;;
    --stall=*) STALL="${1#--stall=}"; shift ;;
    --interval) [[ $# -ge 2 ]] || { usage; exit 2; }; INTERVAL="$2"; shift 2 ;;
    --interval=*) INTERVAL="${1#--interval=}"; shift ;;
    -h|--help) usage; exit 2 ;;
    *) usage; exit 2 ;;
  esac
done

[[ -n "$PID" && -n "$OUT" ]] || { usage; exit 2; }
is_uint "$PID" || { usage; die "invalid --pid: $PID"; }
(( PID > 0 )) || { usage; die "invalid --pid: $PID"; }
is_uint "$MAX" || { usage; die "invalid --max: $MAX"; }
is_uint "$STALL" || { usage; die "invalid --stall: $STALL"; }
is_uint "$INTERVAL" || { usage; die "invalid --interval: $INTERVAL"; }
(( MAX > 0 && STALL > 0 && INTERVAL > 0 )) || { usage; die "timers must be > 0"; }

WORKTREE_SRC="${WORKTREE:-$(pwd)}"
if ! WORKTREE="$(cd "$WORKTREE_SRC" 2>/dev/null && pwd)"; then
  die "worktree not found: $WORKTREE_SRC"
fi

SESSION_ROOT="$HOME/.pi/agent/sessions"
slug="$(printf '%s' "$WORKTREE" | sed 's#/#-#g')"
PRIMARY_DIR="$SESSION_ROOT/-${slug}--"
WATCH_START="$(date +%s)"

heartbeat_mtime() {
  local mtime=""
  if mtime="$(newest_mtime_in_dir "$PRIMARY_DIR" 2>/dev/null || true)" && [[ -n "$mtime" ]]; then
    printf '%s\n' "$mtime"
    return 0
  fi
  mtime="$(newest_mtime_after "$SESSION_ROOT" "$WATCH_START" 2>/dev/null || true)"
  [[ -n "$mtime" ]] || return 1
  printf '%s\n' "$mtime"
}

while kill -0 "$PID" 2>/dev/null; do
  now="$(date +%s)"
  elapsed=$(( now - WATCH_START ))
  hb_mtime=""
  hb_age="n/a"
  if hb_mtime="$(heartbeat_mtime 2>/dev/null || true)" && [[ -n "$hb_mtime" ]]; then
    hb_age=$(( now - hb_mtime ))
  fi
  hb_age_display="$hb_age"
  [[ "$hb_age_display" == n/a ]] || hb_age_display="${hb_age_display}s"
  echo "[worker-watch] t+${elapsed}s pid=alive hb_age=${hb_age_display}" >&2

  if (( elapsed >= MAX )); then
    kill "$PID" 2>/dev/null || true
    echo "STATUS=KILLED_TIMEOUT"
    exit 124
  fi

  if [[ -n "$hb_mtime" ]] && (( hb_age >= STALL )); then
    kill "$PID" 2>/dev/null || true
    echo "STATUS=KILLED_STALLED"
    exit 125
  fi

  sleep "$INTERVAL"
done

if [[ -f "$OUT" ]] && { grep -q 'EXIT=0' "$OUT" 2>/dev/null || grep -q 'CTB-DONE' "$OUT" 2>/dev/null; }; then
  echo "STATUS=DONE"
  exit 0
fi

echo "STATUS=CRASHED"
if [[ -f "$OUT" ]]; then
  tail -n 8 "$OUT" >&2 || true
else
  echo "[worker-watch] out file missing: $OUT" >&2
fi
exit 1
