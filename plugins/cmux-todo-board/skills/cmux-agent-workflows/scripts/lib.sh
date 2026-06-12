#!/usr/bin/env bash
# Shared helpers for cmux orchestration scripts. Source this, don't run it.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
log() { [[ "${LOG_LEVEL:-info}" == "quiet" ]] && return 0; echo ">> $*" >&2; }

# All surface refs currently in the cmux tree (across all windows).
# Surface leaf objects carry their ref in `.ref` (e.g. "surface:169") and a `.tty`.
cmux_surfaces() {
  cmux tree --all --json \
    | jq -r '.. | objects | select((.ref? // "") | startswith("surface:")) | .ref' \
    | sort -u
}

# tty device for a given surface ref, e.g. cmux_tty surface:169 -> ttys005
cmux_tty() {
  local surface="$1"
  cmux tree --all --json \
    | jq -r --arg s "$surface" '.. | objects | select(.ref? == $s) | .tty? // empty' \
    | head -1
}

# Rock-band name pool for agent tab labels.
BAND_POOL=(
  Nirvana Metallica Radiohead Pixies Ramones "Pearl Jam" Soundgarden Tool
  Aerosmith Muse Blur Oasis Queen Rush Kiss Pantera Slipknot Deftones Korn
  Mastodon Megadeth Anthrax Clutch Ghost Opeth Journey Foreigner Heart Cream
  Doors Eagles Kansas Boston Genesis Yes Toto Sabbath Priest Maiden Motorhead
  Dio Scorpions Whitesnake Europe Survivor Triumph Styx Asia Police Clash Cure
  Smiths Garbage Hole Bush Filter Staind Creed Disturbed Godsmack Shinedown
  Audioslave Helmet Fugazi Sevendust Tesla Poison Ratt Warrant Cinderella
)

# All band names currently in use as cmux tab/surface titles (across all windows).
cmux_used_bands() {
  cmux tree --all --json 2>/dev/null \
    | jq -r '.. | objects | .title? // empty' || true
}

# Pick a random band from the pool that is NOT already a live tab title.
# Falls back to "<Band>-<rand>" if the whole pool is somehow in use.
pick_band() {
  local used; used="$(cmux_used_bands)"
  local available=()
  local b
  for b in "${BAND_POOL[@]}"; do
    grep -qiF "$b" <<<"$used" || available+=("$b")
  done
  if (( ${#available[@]} == 0 )); then
    echo "${BAND_POOL[RANDOM % ${#BAND_POOL[@]}]}-$RANDOM"
  else
    echo "${available[RANDOM % ${#available[@]}]}"
  fi
}

# ─── Agent-kind dispatch (pi) ─────────────────────────────────────────────
# The worker runtime is pi-only. The spawn/send/kill scripts share the same
# cmux hooks + tab-naming conventions.

AGENT_KINDS=(pi)

agent_kind_supported() {
  local k="$1"
  for a in "${AGENT_KINDS[@]}"; do [[ "$a" == "$k" ]] && return 0; done
  return 1
}

# Agent kind is always pi (the only runtime). Kept as a function for
# backward-compatible callers.
agent_kind_detect() {
  echo "pi"
}

# Build the launch command for pi (the only agent kind). Echoes a single
# string that the caller pipes to `cmux send --surface <s> "..."` followed by
# a newline. The next two positional args after model are optionally consumed
# as thinking (Pi enum: off|minimal|low|medium|high|xhigh) and tools.
# Remaining args after that are appended verbatim. Non-pi kinds die.
agent_launch_cmd() {
  local kind="$1" wt="$2" model="$3"; shift 3
  case "$kind" in
    pi)
      local provider="${model%%/*}" pi_model="${model#*/}"
      if [[ "$provider" == "$model" ]]; then
        die "pi requires a provider/model form, e.g. opencode-go/deepseek-v4-pro"
      fi
      local thinking="" tools=""
      # Consume thinking if next arg is a valid Pi thinking level (full enum).
      # Only profile-pathed calls pass these; extra-arg passthrough is unaffected
      # because values like "-c" or "extra1" don't match the enum.
      if [[ $# -gt 0 ]]; then
        case "$1" in
          off|minimal|low|medium|high|xhigh) thinking="$1"; shift ;;
        esac
      fi
      # Consume tools if thinking was set (profile path always passes both).
      if [[ -n "$thinking" && $# -gt 0 ]]; then
        tools="$1"; shift
      fi
      printf "cd '%s' && pi --provider %s --model %s" "$wt" "$provider" "$pi_model"
      [[ -n "$thinking" ]] && printf ' --thinking %s' "$thinking"
      [[ -n "$tools" ]] && printf ' --tools %s' "$tools"
      ;;
    *) die "unsupported agent kind: $kind  (only pi is supported)" ;;
  esac
  if (( $# > 0 )); then printf ' %s' "$@"; fi
  printf '\n'
}

# Readiness-screen patterns per agent kind. The first line of `cmux read-screen`
# is grepped for these (extended regex). The trust prompt for codex is handled
# separately (sends "1" + Enter to auto-accept the new directory).
agent_ready_patterns() {
  # The Pi prompt footer always shows (auto) or (sub) once input-ready;
  # a fresh prompt also shows an "esc to interrupt" hint.
  printf '%s' '\(auto\)|\(sub\)|esc.{0,3}interrupt'
}

# Wait until a pi agent is ready in a surface.
#   surface : the cmux surface ref (e.g. surface:172)
#   kind    : pi (only supported kind; kept for callers)
#   timeout : seconds (default 90)
wait_agent_ready() {
  local surface="$1" kind="${2:-pi}" timeout="${3:-90}" waited=0
  local pattern
  pattern="$(agent_ready_patterns "$kind")"
  while (( waited < timeout )); do
    local screen normalized
    screen="$(cmux read-screen --surface "$surface" --lines 40 2>/dev/null || true)"
    # Normalize: delete ALL whitespace + box-drawing chars for pi TUI (#54).
    # Box chars: ┃┏┓┗┛━╹▀│─┌┐└┘●
    normalized="$(printf '%s' "$screen" | tr -d '[:space:]┃┏┓┗┛━╹▀│─┌┐└┘●')"
    if grep -qE "$pattern" <<<"$normalized"; then
      return 0
    fi
    sleep 3; waited=$((waited+3))
  done
  return 1
}

# ps-grep pattern for processes to kill when tearing down an agent surface.
# Covers the main agent binary + helpers (node/bun for embedded JS runtimes).
agent_kill_pattern() {
  printf '%s' 'pi --provider|pi --model'
}

# ─── Balanced grid layout (#97) ──────────────────────────────────────────
# Inspect the current cmux pane tree and pick a target surface + split
# direction so new worker panes are distributed evenly across a balanced
# grid. The orchestrator pane ($CMUX_SURFACE_ID / caller) is never chosen
# as a target, so it is never subdivided.
#
# Output: "<target-surface-ref> <direction>" on success (direction ∈
# right|down), or nothing on failure → caller falls back to legacy
# `cmux new-split <dir>`.
#
# Selection rule (simple + deterministic):
#   - Worker panes = terminal panes in the current workspace whose selected
#     surface ref is NOT the orchestrator (caller) surface.
#   - If 0 worker panes exist: pick the first non-orchestrator leaf (any
#     type, lowest surface number). If none exists (e.g. only the
#     orchestrator pane in the workspace), return empty.
#   - If ≥1 worker panes: pick the worker pane with the lowest surface
#     number (shallowest tie-break, since the cmux JSON is flat).
#   - Direction: alternate for balance — if the count of existing worker
#     panes is even → right, if odd → down. This yields: 1→down, 2→right,
#     3→down, 4→right (approx 2×2 for four workers).
grid_pick_split() {
  local tree_json orch_surface ws_ref
  tree_json="$(cmux tree --all --json 2>/dev/null)" || return 1

  # The orchestrator surface is the caller (who invoked this script/cmux tree).
  orch_surface="$(echo "$tree_json" | jq -r '.caller.surface_ref // empty')"
  [[ -z "$orch_surface" ]] && return 1

  # Determine workspace: try $CMUX_WORKSPACE_ID first, else caller's.
  if [[ -n "${CMUX_WORKSPACE_ID:-}" ]]; then
    ws_ref="$(echo "$tree_json" | jq -r --arg ws "$CMUX_WORKSPACE_ID" \
      '.windows[].workspaces[] | select(.ref == $ws) | .ref' | head -1)"
  fi
  [[ -z "${ws_ref:-}" ]] && ws_ref="$(echo "$tree_json" | jq -r '.caller.workspace_ref // empty')"
  [[ -z "$ws_ref" ]] && return 1

  # Worker surfaces: terminal, selected surfaces in this workspace, excluding orchestrator.
  # Sorted by surface number (lowest first) for deterministic tie-break.
  local worker_refs
  worker_refs="$(echo "$tree_json" | jq -r --arg ws "$ws_ref" --arg orch "$orch_surface" '
    [ .windows[].workspaces[] | select(.ref == $ws) |
      .panes[] |
      . as $pane |
      .surfaces[] | select(.ref == $pane.selected_surface_ref) |
      select(.type == "terminal" and .ref != $orch) |
      .ref
    ] | sort | .[]
  ')"

  # Non-orchestrator leaves (any type) for the 0-worker fallback.
  local non_orch_refs
  non_orch_refs="$(echo "$tree_json" | jq -r --arg ws "$ws_ref" --arg orch "$orch_surface" '
    [ .windows[].workspaces[] | select(.ref == $ws) |
      .panes[] |
      . as $pane |
      .surfaces[] | select(.ref == $pane.selected_surface_ref) |
      select(.ref != $orch) |
      .ref
    ] | sort | .[]
  ')"

  # Count existing worker panes.
  local worker_count=0
  if [[ -n "$worker_refs" ]]; then
    worker_count="$(echo "$worker_refs" | grep -c '^surface:' || echo 0)"
  fi

  local target="" dir=""

  if [[ "$worker_count" -eq 0 ]]; then
    # 0 workers: pick the first non-orchestrator leaf (any type).
    target="$(echo "$non_orch_refs" | head -1)"
    [[ -z "$target" ]] && return 1  # only orchestrator exists → legacy fallback
    dir="right"
  else
    # ≥1 workers: pick the shallowest (lowest surface number, already sorted).
    target="$(echo "$worker_refs" | head -1)"
    # Alternate direction: even → right, odd → down  (2×2 for 4 workers).
    if (( worker_count % 2 == 0 )); then
      dir="right"
    else
      dir="down"
    fi
  fi

  [[ -z "$target" || -z "$dir" ]] && return 1
  echo "$target $dir"
}
