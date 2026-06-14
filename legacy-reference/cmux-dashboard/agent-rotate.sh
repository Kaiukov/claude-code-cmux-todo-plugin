#!/usr/bin/env bash
# agent-rotate.sh — find first idle worker pane, clean it, launch fresh pi agent
#
# Usage: ./agent-rotate.sh [--model <provider/model>] [--cwd <path>] [--thinking <level>]
#
# Flow:
#   1. List all panes in current workspace
#   2. Skip orchestrator (caller)
#   3. Find first candidate:
#      a. No pi process → empty slot → launch pi directly
#      b. Pi process + idle (ready prompt) → send /exit, sleep 5, launch new pi
#   4. Launch pi with damage-control extension
#
# Safety — NEVER touches:
#   - The orchestrator's own surface ($CMUX_SURFACE_ID)
#   - Panes with active (busy) pi agents
set -euo pipefail

CMUX="${CMUX:-cmux}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── defaults ─────────────────────────────────────────────────────────────
PROVIDER="opencode-go"
MODEL="deepseek-v4-pro"
THINKING="high"
CWD="${CWD:-$(pwd)}"
DAMAGE_CTL=""
CMUX_QUIET="${CMUX_QUIET:-1}"

# Find damage-control extension
for candidate in \
  "$SCRIPT_DIR/damage-control.ts" \
  "$SCRIPT_DIR/../../../.pi/extensions/damage-control.ts" \
  "$HOME/.pi/extensions/damage-control.ts"; do
  if [[ -f "$candidate" ]]; then
    DAMAGE_CTL="$candidate"
    break
  fi
done

# ─── arg parse ────────────────────────────────────────────────────────────
while (( $# > 0 )); do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    --model=*) MODEL="${1#--model=}"; shift ;;
    --cwd) CWD="$2"; shift 2 ;;
    --cwd=*) CWD="${1#--cwd=}"; shift ;;
    --thinking) THINKING="$2"; shift 2 ;;
    --thinking=*) THINKING="${1#--thinking=}"; shift ;;
    -h|--help)
      sed -n '2,20p' "$0"; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Split provider/model
if [[ "$MODEL" == */* ]]; then
  PROVIDER="${MODEL%%/*}"
  MODEL="${MODEL#*/}"
fi

# ─── helpers ──────────────────────────────────────────────────────────────
die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "  → $*" >&2; }

cmux_tty() {
  cmux tree --all --json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
for w in d.get('windows', []):
    for ws in w.get('workspaces', []):
        for p in ws.get('panes', []):
            for s in p.get('surfaces', []):
                if s.get('ref') == '$1':
                    print(s.get('tty', ''))
                    sys.exit(0)
" 2>/dev/null
}

pi_running() {
  local tty="$1"
  [[ -n "$tty" ]] || return 1
  ps -t "$tty" -o comm= 2>/dev/null | grep -qE '^pi$' && return 0 || return 1
}

# True if pi is IDLE (prompt visible, no spinner/busy indicator)
# Key insight: (auto) is always in the status bar. The real busy signal is the
# "⠴ Working..." / "⠙ Thinking..." spinner line. If that's absent, pi is idle.
pi_idle() {
  local surface="$1"
  local screen norm
  screen="$(cmux read-screen --surface "$surface" --lines 15 2>/dev/null || true)"
  norm="$(printf '%s' "$screen" | tr -d '[:space:]')"
  # Must have prompt (pi is alive) AND no spinner (pi is idle)
  if echo "$norm" | grep -qE '\(auto\)|\(sub\)'; then
    # Pi is alive — check if it's actually working
    echo "$norm" | grep -q 'Working\.\.\.' && return 1  # busy
    echo "$norm" | grep -q 'Thinking\.\.\.' && return 1  # busy
    return 0  # idle
  fi
  return 1  # not at prompt (booting? crashed?)
}

# ─── detect workspace ────────────────────────────────────────────────────
CTX="$(cmux identify --json 2>&1)" || die "cmux identify failed"
WS="$(echo "$CTX" | python3 -c "import json,sys; print(json.load(sys.stdin)['caller']['workspace_ref'])")"
ORCH_SURF="$(echo "$CTX" | python3 -c "import json,sys; print(json.load(sys.stdin)['caller']['surface_ref'])")"
info "workspace: $WS  orchestrator: $ORCH_SURF"

# ─── list worker surfaces ─────────────────────────────────────────────────
WORKERS=$(cmux list-panes --workspace "$WS" --json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
for p in d.get('panes', []):
    for sref in p.get('surface_refs', []):
        print(sref)
" 2>/dev/null) || die "failed to list panes"

COUNT=$(echo "$WORKERS" | wc -l | tr -d ' ')
info "scanning $COUNT surfaces..."

# ─── find first candidate ────────────────────────────────────────────────
CANDIDATE=""
CANDIDATE_TTY=""
CANDIDATE_STATE=""  # "empty" | "idle"

while IFS= read -r surf; do
  [[ -z "$surf" ]] && continue

  # Skip orchestrator
  if [[ "$surf" == "$ORCH_SURF" ]]; then
    info "skip $surf (orchestrator)"
    continue
  fi

  # Get tty
  TTY="$(cmux_tty "$surf")" || true

  if [[ -z "$TTY" ]]; then
    info "candidate $surf (no tty — empty slot)"
    CANDIDATE="$surf"
    CANDIDATE_STATE="empty"
    break
  fi

  # Check pi process
  if pi_running "$TTY"; then
    # Pi is running — check if idle
    if pi_idle "$surf"; then
      info "candidate $surf (pi idle, will rotate)"
      CANDIDATE="$surf"
      CANDIDATE_TTY="$TTY"
      CANDIDATE_STATE="idle"
      break
    else
      info "skip $surf (pi busy)"
    fi
  else
    # No pi process in this tty — empty slot (shell only)
    info "candidate $surf (no agent — empty slot)"
    CANDIDATE="$surf"
    CANDIDATE_TTY="$TTY"
    CANDIDATE_STATE="empty"
    break
  fi
done <<< "$WORKERS"

if [[ -z "$CANDIDATE" ]]; then
  die "no free/idle worker panes found — all busy or no worker panes available"
fi

info "selected $CANDIDATE (state=$CANDIDATE_STATE)"

# ─── clean console ───────────────────────────────────────────────────────
if [[ "$CANDIDATE_STATE" == "idle" ]]; then
  info "sending /exit to quit pi agent..."
  cmux send --surface "$CANDIDATE" "/exit" 2>/dev/null || true
  sleep 1
  cmux send-key --surface "$CANDIDATE" "Enter" 2>/dev/null || true

  info "waiting 5s for pi to exit..."
  sleep 5

  # Verify pi is gone; force kill if stuck
  if [[ -n "$CANDIDATE_TTY" ]] && pi_running "$CANDIDATE_TTY"; then
    info "pi still running — force kill..."
    PIDS=$(ps -t "$CANDIDATE_TTY" -o pid=,comm= 2>/dev/null | grep ' pi$' | awk '{print $1}' || true)
    if [[ -n "$PIDS" ]]; then
      kill $PIDS 2>/dev/null || true
      sleep 2
      kill -9 $PIDS 2>/dev/null || true
    fi
  fi
  info "console cleaned"

elif [[ "$CANDIDATE_STATE" == "empty" ]]; then
  if [[ -n "$CANDIDATE_TTY" ]]; then
    # Shell is running — clear screen
    info "clearing console..."
    cmux send --surface "$CANDIDATE" "clear" 2>/dev/null || true
    sleep 0.3
    cmux send-key --surface "$CANDIDATE" "Enter" 2>/dev/null || true
    sleep 0.2
  else
    info "no tty — surface may need cmux to respawn terminal"
  fi
fi

# ─── pre-seed pi trust ───────────────────────────────────────────────────
mkdir -p ~/.pi/agent
[[ -f ~/.pi/agent/trust.json ]] || echo '{}' > ~/.pi/agent/trust.json
python3 -c "
import json
with open('$HOME/.pi/agent/trust.json') as f:
    t = json.load(f)
t['$CWD'] = True
with open('$HOME/.pi/agent/trust.json', 'w') as f:
    json.dump(t, f, indent=2)
" 2>/dev/null

# ─── launch new pi agent ─────────────────────────────────────────────────
EXTRA_ARGS=()
[[ -n "$DAMAGE_CTL" && -f "$DAMAGE_CTL" ]] && EXTRA_ARGS+=("--extension" "$DAMAGE_CTL")

LAUNCH_CMD="cd '$CWD' && pi --provider $PROVIDER --model $MODEL --thinking $THINKING"
for arg in "${EXTRA_ARGS[@]}"; do
  LAUNCH_CMD="$LAUNCH_CMD $arg"
done

info "launching: $LAUNCH_CMD"
cmux send --surface "$CANDIDATE" "$LAUNCH_CMD" 2>/dev/null || true
sleep 1
cmux send-key --surface "$CANDIDATE" "Enter" 2>/dev/null || true

# ─── wait for pi ready ──────────────────────────────────────────────────
info "waiting for pi to boot..."
for i in $(seq 1 20); do
  sleep 3
  if pi_idle "$CANDIDATE"; then
    info "✓ pi ready in $CANDIDATE after ${i}x3=$((i*3))s"
    echo "$CANDIDATE"
    exit 0
  fi
  echo -n "." >&2
done

info "⚠ pi not confirmed ready after 60s — launched but may need manual check"
echo "$CANDIDATE"
