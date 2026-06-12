#!/usr/bin/env bash
# Split the current pane, boot an agent (opencode or codex) in a worktree, wait
# until ready, and label the tab. Echoes the NEW surface ref on success.
#
# Usage: agent-spawn.sh <dir> <worktree> <model> [label] [extra agent args...] [--agent pi] [--profile <name>]
#   agent-spawn.sh right /Users/x/Code/mpc-108 opencode-go/deepseek-v4-pro 108
#   agent-spawn.sh right /Users/x/Code/mpc-108 --profile backend 108
#
# The tab name is auto-assigned: a RANDOM rock band not already in use is picked
# from the pool (so names never repeat across live agents — no manual naming).
# The optional [label] (e.g. an issue number) is appended → "Radiohead 108".
# Any args after [label] are forwarded verbatim to the agent launch command
# (e.g. `-c model_reasoning_effort=high` for codex).
#
# The only agent kind is pi (default when --agent is omitted).
#
# Live deploy / KV writes stay orchestrator-only — agents implement + mock only.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/lib.sh"

# --- arg parse: extract --agent + --profile (anywhere in argv) then positionals --------
AGENT_KIND=""
PROFILE=""
ARGS=()
while (( $# > 0 )); do
  case "$1" in
    --agent) AGENT_KIND="$2"; shift 2 ;;
    --agent=*) AGENT_KIND="${1#--agent=}"; shift ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --profile=*) PROFILE="${1#--profile=}"; shift ;;
    --quiet) LOG_LEVEL=quiet; shift ;;
    -h|--help)
      sed -n '2,17p' "$0"; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

if [[ -n "$PROFILE" ]]; then
  # --profile implies --agent pi
  [[ -z "$AGENT_KIND" ]] && AGENT_KIND="pi"
  # --profile and explicit --model are mutually exclusive (model comes from profile)
  # MODEL will be set from profile resolution below; detect if user passed a model positionally
  (( ${#ARGS[@]} >= 2 )) || die "usage: agent-spawn.sh <dir> <worktree> --profile <name> [label] [extra agent args...]"
  SPLIT="${ARGS[0]}"; WT="${ARGS[1]}"
  # If a 3rd positional arg is present, it's a label (model is from profile, not positional)
  LABEL="${ARGS[2]:-}"
  EXTRA=("${ARGS[@]:3}")
  # Resolve profile via board-config
  REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
  if ! PROFILE_JSON="$(REPO_ROOT="$REPO_ROOT" "$REPO_ROOT/bin/board-config" --get-profile "$PROFILE" --json 2>&1)"; then
    die "board-config --get-profile $PROFILE failed: $PROFILE_JSON"
  fi
  log "resolved profile $PROFILE → $PROFILE_JSON"
  MODEL="$(echo "$PROFILE_JSON" | jq -r '.provider')/$(echo "$PROFILE_JSON" | jq -r '.model')"
  PROFILE_THINKING="$(echo "$PROFILE_JSON" | jq -r '.thinking')"
  PROFILE_TOOLS="$(echo "$PROFILE_JSON" | jq -r '.tools')"
  log "profile model: $MODEL  thinking: $PROFILE_THINKING  tools: $PROFILE_TOOLS"
else
  (( ${#ARGS[@]} >= 3 )) || die "usage: agent-spawn.sh <dir> <worktree> <model> [label] [extra agent args...] [--agent pi] [--profile <name>]"
  SPLIT="${ARGS[0]}"; WT="${ARGS[1]}"; MODEL="${ARGS[2]}"; LABEL="${ARGS[3]:-}"
  # Any positionals after [label] are forwarded verbatim to the agent launch
  # command (e.g. `-c model_reasoning_effort=high` for codex).
  EXTRA=("${ARGS[@]:4}")
fi
[[ -d "$WT" ]] || die "worktree not found: $WT"

# Resolve tier names (flash|pro|review|simple|top) via board-config.
# Raw model ids (e.g. "deepseek/deepseek-v4-pro") pass through unchanged.
# When a registry entry provides a provider override or reasoning effort,
# consume those flags as well so dispatch uses the configured backend and
# forwards the effort to the agent launch command.
RESOLVED_PROVIDER=""
RESOLVED_EFFORT=""
case "$MODEL" in
  flash|pro|review|simple|top)
    REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
    if ! RESOLVED="$(REPO_ROOT="$REPO_ROOT" "$REPO_ROOT/bin/board-config" --get-model "$MODEL" 2>/dev/null)"; then
      die "board-config --get-model $MODEL failed"
    fi
    log "resolved tier $MODEL → $RESOLVED"
    if PROVIDER="$(REPO_ROOT="$REPO_ROOT" "$REPO_ROOT/bin/board-config" --get-model "$MODEL" --provider 2>/dev/null)" && [[ -n "$PROVIDER" ]]; then
      RESOLVED_PROVIDER="$PROVIDER"
      log "resolved provider: $RESOLVED_PROVIDER"
    fi
    if EFFORT="$(REPO_ROOT="$REPO_ROOT" "$REPO_ROOT/bin/board-config" --get-model "$MODEL" --effort 2>/dev/null)" && [[ -n "$EFFORT" ]]; then
      RESOLVED_EFFORT="$EFFORT"
      log "resolved effort: $RESOLVED_EFFORT"
    fi
    MODEL="$RESOLVED"
    ;;
esac

# Normalize the model to the CANONICAL provider per docs/models.json. The paid
# opencode gateway for DeepSeek is `opencode-go/…`; the bare name or a direct
# `deepseek/…` provider hits a different (unfunded) account. Rewrite both forms
# so a wrong provider can't slip through.
case "$MODEL" in
  deepseek-v4-pro|deepseek-v4-flash) MODEL="opencode-go/$MODEL"; log "normalized model → $MODEL" ;;
  deepseek/deepseek-v4-pro|deepseek/deepseek-v4-flash) MODEL="opencode-go/${MODEL#deepseek/}"; log "normalized provider deepseek→opencode-go: $MODEL" ;;
esac

# Resolve agent kind: explicit --agent flag > registry provider > auto-detect.
if [[ -n "$AGENT_KIND" ]]; then
  agent_kind_supported "$AGENT_KIND" || die "unknown --agent: $AGENT_KIND  (supported: ${AGENT_KINDS[*]})"
elif [[ -n "$RESOLVED_PROVIDER" ]]; then
  agent_kind_supported "$RESOLVED_PROVIDER" || die "unknown provider from board-config: $RESOLVED_PROVIDER  (supported: ${AGENT_KINDS[*]})"
  AGENT_KIND="$RESOLVED_PROVIDER"
else
  AGENT_KIND="$(agent_kind_detect "$MODEL")"
fi
log "agent kind: $AGENT_KIND  (model: $MODEL)"

# Verify the agent binary is on PATH; bail with a clear error otherwise.
case "$AGENT_KIND" in
  pi) command -v pi >/dev/null || die "pi not on PATH" ;;
esac

BAND="$(pick_band)"
NAME="$BAND${LABEL:+ $LABEL}"
log "auto-named agent: $NAME"

# Try balanced grid layout — explicit target, never split orchestrator pane
GRID_RESULT="$(grid_pick_split 2>/dev/null || true)"
if [[ -n "$GRID_RESULT" ]]; then
  TARGET="${GRID_RESULT%% *}"
  HELPER_DIR="${GRID_RESULT##* }"
  # Caller's SPLIT direction (always a direction: left/right/up/down) wins.
  SPLIT_DIR="$SPLIT"
  case "$SPLIT" in left|right|up|down) ;; *) SPLIT_DIR="$HELPER_DIR" ;; esac
  log "splitting $SPLIT_DIR from $TARGET (grid-balanced)"
  SPLIT_OUT="$(cmux new-split "$SPLIT_DIR" --surface "$TARGET" 2>&1)"
else
  log "splitting $SPLIT (legacy)"
  SPLIT_OUT="$(cmux new-split "$SPLIT" 2>&1)"
fi
SURFACE="$(echo "$SPLIT_OUT" | grep -oE 'surface:[0-9]+' | head -1)"
[[ -n "$SURFACE" ]] || die "could not determine new surface ref from output: $SPLIT_OUT"
log "new surface: $SURFACE"

cmux rename-tab --surface "$SURFACE" "$NAME" >&2 || true
# Pre-seed Pi trust so it doesn't show a trust prompt for this worktree.
if [[ "$AGENT_KIND" == "pi" ]]; then
  mkdir -p ~/.pi/agent
  [[ -f ~/.pi/agent/trust.json ]] || echo '{}' > ~/.pi/agent/trust.json
  jq --arg wt "$WT" '. + {($wt): true}' ~/.pi/agent/trust.json > ~/.pi/agent/trust.json.tmp \
    && mv ~/.pi/agent/trust.json.tmp ~/.pi/agent/trust.json
  log "pre-seeded pi trust for $WT"
fi

# --- #91 damage-control safety gate ---
# Load the damage-control extension for Pi workers so every bash invocation
# is checked against .pi/damage-control-rules.yaml (deny/ask safety net).
if [[ "$AGENT_KIND" == "pi" ]]; then
  EXTRA+=("--extension" "$DIR/../../../../../.pi/extensions/damage-control.ts")
  log "damage-control: appended --extension for pi worker"
fi
# --- end #91 ---

# --- #118 prompt layering ---
# Load canonical Pi worker prompt assets (common-system + per-role guidance).
# Appended via --append-system-prompt so the orchestrator never loads them.
if [[ "$AGENT_KIND" == "pi" ]]; then
  PROMPTS_DIR="$DIR/../../../prompts/pi"
  ROLE="${PROFILE:-backend}"
  EXTRA+=("--append-system-prompt" "$PROMPTS_DIR/common-system.md"
          "--append-system-prompt" "$PROMPTS_DIR/roles/$ROLE.md")
  log "loaded pi prompt assets: common-system + roles/$ROLE"
fi
# --- end #118 ---

log "booting $AGENT_KIND in $WT"
# Send the launch command, then submit it with a discrete Enter key. `cmux send`
# only TYPES the text into the shell — without this send-key the command sits at
# the prompt unexecuted and you'd have to press ENTER by hand every spawn.
if [[ -n "$PROFILE" ]]; then
  cmux send --surface "$SURFACE" -- "$(agent_launch_cmd "$AGENT_KIND" "$WT" "$MODEL" "$PROFILE_THINKING" "$PROFILE_TOOLS" ${EXTRA[@]+"${EXTRA[@]}"})" >&2
else
  cmux send --surface "$SURFACE" -- "$(agent_launch_cmd "$AGENT_KIND" "$WT" "$MODEL" ${EXTRA[@]+"${EXTRA[@]}"})" >&2
fi
sleep 1
cmux send-key --surface "$SURFACE" "Enter" >&2

if wait_agent_ready "$SURFACE" "$AGENT_KIND" 120; then
  log "agent ready in $SURFACE"
else
  log "WARNING: agent not confirmed ready after 120s — check manually"
fi
echo "$SURFACE"
