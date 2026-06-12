#!/usr/bin/env bash
# Split the current pane, boot an agent (opencode or codex) in a worktree, wait
# until ready, and label the tab. Echoes the NEW surface ref on success.
#
# Usage: agent-spawn.sh <dir> <worktree> <model> [label] [extra agent args...] [--agent opencode|codex]
#   agent-spawn.sh right /Users/x/Code/mpc-108 deepseek/deepseek-v4-pro 108
#   agent-spawn.sh right /Users/x/Code/mpc-108 gpt-5-codex 108 --agent codex
#   agent-spawn.sh right /Users/x/Code/mpc-108 gpt-5.4 266 -c model_reasoning_effort=high --agent codex
#
# The tab name is auto-assigned: a RANDOM rock band not already in use is picked
# from the pool (so names never repeat across live agents — no manual naming).
# The optional [label] (e.g. an issue number) is appended → "Radiohead 108".
# Any args after [label] are forwarded verbatim to the agent launch command
# (e.g. `-c model_reasoning_effort=high` for codex).
#
# Agent kinds (auto-detected from model when --agent is omitted):
#   opencode : deepseek/deepseek-v4-pro, opencode-go/kimi-k2, ...  (provider/model)
#   codex    : gpt-5-codex, gpt-5.4, gpt-5.4-mini, o3-mini, o4-mini, codex, ...
# Pass --agent explicitly to override auto-detection.
#
# Live deploy / KV writes stay orchestrator-only — agents implement + mock only.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/lib.sh"

# --- arg parse: extract --agent (anywhere in argv) then positionals --------
AGENT_KIND=""
ARGS=()
while (( $# > 0 )); do
  case "$1" in
    --agent) AGENT_KIND="$2"; shift 2 ;;
    --agent=*) AGENT_KIND="${1#--agent=}"; shift ;;
    --quiet) LOG_LEVEL=quiet; shift ;;
    -h|--help)
      sed -n '2,16p' "$0"; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

(( ${#ARGS[@]} >= 3 )) || die "usage: agent-spawn.sh <dir> <worktree> <model> [label] [extra agent args...] [--agent opencode|codex]"
SPLIT="${ARGS[0]}"; WT="${ARGS[1]}"; MODEL="${ARGS[2]}"; LABEL="${ARGS[3]:-}"
# Any positionals after [label] are forwarded verbatim to the agent launch
# command (e.g. `-c model_reasoning_effort=high` for codex).
EXTRA=("${ARGS[@]:4}")
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
  opencode) command -v opencode >/dev/null || die "opencode not on PATH" ;;
  codex)    command -v codex    >/dev/null || die "codex not on PATH" ;;
  pi)       command -v pi       >/dev/null || die "pi not on PATH" ;;
esac

# Forward registry-resolved reasoning effort to the codex launch command.
# Only applied when (a) an effort was resolved from board-config, (b) the
# agent is codex, and (c) the caller hasn't already passed an explicit
# model_reasoning_effort in the extra positional args.
if [[ -n "$RESOLVED_EFFORT" && "$AGENT_KIND" == "codex" ]]; then
  already_has_effort=""
  for a in "${EXTRA[@]}"; do
    [[ "$a" == "-c" || "$a" == "model_reasoning_effort"* ]] && already_has_effort=1 && break
  done
  if [[ -z "$already_has_effort" ]]; then
    EXTRA+=("-c" "model_reasoning_effort=$RESOLVED_EFFORT")
    log "auto-added -c model_reasoning_effort=$RESOLVED_EFFORT"
  fi
fi

BAND="$(pick_band)"
NAME="$BAND${LABEL:+ $LABEL}"
log "auto-named agent: $NAME"

log "splitting $SPLIT"
SPLIT_OUT="$(cmux new-split "$SPLIT" 2>&1)"
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

log "booting $AGENT_KIND in $WT"
# Send the launch command, then submit it with a discrete Enter key. `cmux send`
# only TYPES the text into the shell — without this send-key the command sits at
# the prompt unexecuted and you'd have to press ENTER by hand every spawn.
cmux send --surface "$SURFACE" -- "$(agent_launch_cmd "$AGENT_KIND" "$WT" "$MODEL" ${EXTRA[@]+"${EXTRA[@]}"})" >&2
sleep 1
cmux send-key --surface "$SURFACE" "Enter" >&2

if wait_agent_ready "$SURFACE" "$AGENT_KIND" 120; then
  log "agent ready in $SURFACE"
else
  log "WARNING: agent not confirmed ready after 120s — check manually"
fi
echo "$SURFACE"
