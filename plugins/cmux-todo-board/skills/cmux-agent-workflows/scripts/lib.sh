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

# ─── Agent-kind dispatch (opencode | codex) ────────────────────────────────
# Supported agent backends the spawn/send/kill scripts understand.
#   opencode : `opencode --model <provider/model>`
#   codex    : `codex --cd <wt> -m <model> -a never`
# Agents share the same cmux hooks + tab-naming conventions; only the launch
# command and the screen-readiness markers differ.

AGENT_KINDS=(opencode codex pi)

agent_kind_supported() {
  local k="$1"
  for a in "${AGENT_KINDS[@]}"; do [[ "$a" == "$k" ]] && return 0; done
  return 1
}

# Auto-detect agent kind from a model identifier when --agent is omitted.
# Codex-style model names: gpt-*, o1-*, o3-*, o4-*, codex*  (and bare names like
# "gpt-5" or "o3-mini" used by `codex -m`). Anything containing a "/" is an
# opencode provider/model string (e.g. "deepseek/deepseek-v4-pro").
agent_kind_detect() {
  local model="$1"
  if [[ -z "$model" ]]; then echo "opencode"; return; fi
  # Provider/model form is always opencode (e.g. "deepseek/deepseek-v4-pro").
  if [[ "$model" == */* ]]; then echo "opencode"; return; fi
  # Lowercase via tr (macOS bash 3.2 lacks ${var,,}). Codex accepts mixed case
  # in config but dispatch rules must be case-insensitive.
  local lc
  lc="$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')"
  case "$lc" in
    gpt-*|o1-*|o3-*|o4-*|codex*|chatgpt-*) echo "codex" ;;
    *) echo "opencode" ;;
  esac
}

# Build the launch command for a given agent kind. Echoes a single string that
# the caller pipes to `cmux send --surface <s> "..."` followed by a newline.
# Extra args (already shell-quoted) are appended.
agent_launch_cmd() {
  local kind="$1" wt="$2" model="$3"; shift 3
  case "$kind" in
    opencode)
      printf "cd '%s' && opencode --model %s" "$wt" "$model"
      ;;
    codex)
      # -a never : never ask for approval (headless delegation agent)
      # -s danger-full-access : skip sandbox so the agent can write inside its
      #   own worktree without workspace-write prompts. Match opencode's
      #   effective sandbox posture (a worktree is the trust boundary).
      printf "codex --cd '%s' -m %s -a never -s danger-full-access" "$wt" "$model"
      ;;
    pi)
      local provider="${model%%/*}" pi_model="${model#*/}"
      if [[ "$provider" == "$model" ]]; then
        die "pi requires a provider/model form, e.g. opencode-go/deepseek-v4-pro"
      fi
      printf "cd '%s' && pi --provider %s --model %s" "$wt" "$provider" "$pi_model"
      ;;
  esac
  if (( $# > 0 )); then printf ' %s' "$@"; fi
  printf '\n'
}

# Readiness-screen patterns per agent kind. The first line of `cmux read-screen`
# is grepped for these (extended regex). The trust prompt for codex is handled
# separately (sends "1" + Enter to auto-accept the new directory).
agent_ready_patterns() {
  case "$1" in
    opencode)
      # Input-ready markers that survive even when the TUI renders as
      # multi-column boxes in very narrow split panes (#54). The model
      # banner becomes column-interleaved garbage, but these horizontal
      # command-bar tokens reliably survive whitespace+box-char stripping:
      #   anything  — the empty-input placeholder in the prompt box
      #   agents    — the agents command-bar button
      #   commands  — the commands command-bar button
      printf '%s' 'anything|agents|commands'
      ;;
    codex)
      # The codex TUI shows the OpenAI Codex banner + model id in the prompt
      # box footer (e.g. "gpt-5-codex medium · /path"). Match on the
      # distinctive "OpenAI Codex" header.
      printf '%s' 'OpenAI Codex|codex-cli|_> OpenAI Codex'
      ;;
    pi)
      # The Pi prompt footer always shows (auto) or (sub) once input-ready;
      # a fresh prompt also shows an "esc to interrupt" hint.
      printf '%s' '\(auto\)|\(sub\)|esc.{0,3}interrupt'
      ;;
  esac
}

# True if the screen currently shows the codex "trust this directory?" prompt.
# We auto-accept for delegation agents (they own their worktree).
is_trust_prompt() {
  cmux read-screen --surface "$1" --lines 30 2>/dev/null \
    | grep -qE 'Do you trust the contents of this directory\?|Yes, continue'
}

# Wait until an agent (opencode or codex) is ready in a surface.
# Handles the codex trust prompt by sending "1\n" to auto-accept.
#   surface : the cmux surface ref (e.g. surface:172)
#   kind    : opencode | codex
#   timeout : seconds (default 90)
wait_agent_ready() {
  local surface="$1" kind="${2:-opencode}" timeout="${3:-90}" waited=0
  local pattern trust_seen=""
  pattern="$(agent_ready_patterns "$kind")"
  while (( waited < timeout )); do
    local screen normalized
    screen="$(cmux read-screen --surface "$surface" --lines 40 2>/dev/null || true)"
    # Normalize: opencode TUI can render as multi-column boxes in narrow
    # panes so we delete ALL whitespace + box-drawing chars (#54).
    # Codex TUI does not have this problem — collapse whitespace only.
    # Pi uses the same normalization as opencode (box-drawing chars in TUI).
    # Box chars: ┃┏┓┗┛━╹▀│─┌┐└┘●
    if [[ "$kind" == "opencode" || "$kind" == "pi" ]]; then
      normalized="$(printf '%s' "$screen" | tr -d '[:space:]┃┏┓┗┛━╹▀│─┌┐└┘●')"
    else
      normalized="$(printf '%s' "$screen" | tr -s ' \n' ' ')"
    fi
    if [[ "$kind" == "codex" && -z "$trust_seen" ]] \
         && grep -qE 'Do you trust the contents of this directory' <<<"$screen"; then
      log "auto-accepting codex trust prompt in $surface"
      cmux send --surface "$surface" -- "1" >&2
      sleep 1
      cmux send-key --surface "$surface" "Enter" >&2
      trust_seen=1
      sleep 3; waited=$((waited+4))
      continue
    fi
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
  case "$1" in
    opencode) printf '%s' 'opencode|node|bun' ;;
    codex)    printf '%s' 'codex|node|bun' ;;
    pi)       printf '%s' 'pi --provider|pi --model' ;;
    *)        printf '%s' 'opencode|codex|node|bun' ;;
  esac
}
