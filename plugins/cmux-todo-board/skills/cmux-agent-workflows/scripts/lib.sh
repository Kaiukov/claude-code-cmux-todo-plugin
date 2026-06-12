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
