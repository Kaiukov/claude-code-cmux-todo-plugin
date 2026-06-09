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
case "$MODEL" in
  flash|pro|review|simple|top)
    REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
    if ! RESOLVED="$(REPO_ROOT="$REPO_ROOT" "$REPO_ROOT/bin/board-config" --get-model "$MODEL" 2>/dev/null)"; then
      die "board-config --get-model $MODEL failed"
    fi
    log "resolved tier $MODEL → $RESOLVED"
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

# Resolve agent kind: explicit flag wins, else auto-detect from the model.
if [[ -n "$AGENT_KIND" ]]; then
  agent_kind_supported "$AGENT_KIND" || die "unknown --agent: $AGENT_KIND  (supported: ${AGENT_KINDS[*]})"
else
  AGENT_KIND="$(agent_kind_detect "$MODEL")"
fi
log "agent kind: $AGENT_KIND  (model: $MODEL)"

# Verify the agent binary is on PATH; bail with a clear error otherwise.
case "$AGENT_KIND" in
  opencode) command -v opencode >/dev/null || die "opencode not on PATH" ;;
  codex)    command -v codex    >/dev/null || die "codex not on PATH" ;;
esac

BAND="$(pick_band)"
NAME="$BAND${LABEL:+ $LABEL}"
log "auto-named agent: $NAME"

BEFORE="$(cmux_surfaces)"
log "splitting $SPLIT"
cmux new-split "$SPLIT" >&2
sleep 1
AFTER="$(cmux_surfaces)"

SURFACE="$(comm -13 <(echo "$BEFORE") <(echo "$AFTER") | head -1)"
[[ -n "$SURFACE" ]] || die "could not determine new surface ref"
log "new surface: $SURFACE"

cmux rename-tab --surface "$SURFACE" "$NAME" >&2 || true
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
