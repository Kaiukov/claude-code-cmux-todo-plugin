#!/usr/bin/env bash
# Headless pi worker launcher.
# Canonical waiter / liveness watchdog: worker-watch.sh --pid <PID> --out <WT>/out.json --worktree <WT>
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: worker-spawn.sh <worktree> --profile <name> [label] [--thinking <level>] [--tools <csv>] [--role <name>]
       worker-spawn.sh <worktree> <model> [label] [--thinking <level>] [--tools <csv>] [--role <name>]
EOF
}

normalize_provider_model() {
  local provider="$1" model="$2"
  case "$provider/$model" in
    deepseek/deepseek-v4-pro|deepseek/deepseek-v4-flash)
      provider="opencode-go"
      ;;
  esac
  printf '%s %s\n' "$provider" "$model"
}

parse_raw_model() {
  local raw="$1" provider model
  case "$raw" in
    deepseek-v4-pro|deepseek-v4-flash)
      provider="opencode-go"
      model="$raw"
      ;;
    */*)
      provider="${raw%%/*}"
      model="${raw#*/}"
      case "$provider/$model" in
        deepseek/deepseek-v4-pro|deepseek/deepseek-v4-flash)
          provider="opencode-go"
          ;;
      esac
      ;;
    *)
      die "raw model must be provider/model or deepseek-v4-pro|deepseek-v4-flash"
      ;;
  esac
  printf '%s %s\n' "$provider" "$model"
}

PROFILE=""
THINKING_OVERRIDE=""
TOOLS_OVERRIDE=""
ROLE_OVERRIDE=""
ARGS=()
while (( $# > 0 )); do
  case "$1" in
    --profile) [[ $# -ge 2 ]] || { usage; exit 2; }; PROFILE="$2"; shift 2 ;;
    --profile=*) PROFILE="${1#--profile=}"; shift ;;
    --thinking) [[ $# -ge 2 ]] || { usage; exit 2; }; THINKING_OVERRIDE="$2"; shift 2 ;;
    --thinking=*) THINKING_OVERRIDE="${1#--thinking=}"; shift ;;
    --tools) [[ $# -ge 2 ]] || { usage; exit 2; }; TOOLS_OVERRIDE="$2"; shift 2 ;;
    --tools=*) TOOLS_OVERRIDE="${1#--tools=}"; shift ;;
    --role) [[ $# -ge 2 ]] || { usage; exit 2; }; ROLE_OVERRIDE="$2"; shift 2 ;;
    --role=*) ROLE_OVERRIDE="${1#--role=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

(( ${#ARGS[@]} >= 1 )) || { usage; exit 2; }
WT="${ARGS[0]}"
[[ -d "$WT" ]] || die "worktree not found: $WT"
WT="$(cd "$WT" && pwd)"

MODEL=""
THINKING="medium"
TOOLS="read,edit,write,grep,find,ls,bash"
ROLE="backend"
LABEL=""

if [[ -n "$PROFILE" ]]; then
  (( ${#ARGS[@]} <= 2 )) || { usage; die "too many args for --profile mode"; }
  LABEL="${ARGS[1]:-}"
  REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
  if ! PROFILE_JSON="$($REPO_ROOT/bin/board-config --get-profile "$PROFILE" --json 2>&1)"; then
    die "board-config --get-profile $PROFILE failed: $PROFILE_JSON"
  fi
  PROVIDER="$(jq -r '.provider' <<<"$PROFILE_JSON")"
  MODEL="$(jq -r '.model' <<<"$PROFILE_JSON")"
  THINKING="$(jq -r '.thinking' <<<"$PROFILE_JSON")"
  TOOLS="$(jq -r '.tools' <<<"$PROFILE_JSON")"
  ROLE="$(jq -r '.role // "backend"' <<<"$PROFILE_JSON")"
  PROVIDER_MODEL="$(normalize_provider_model "$PROVIDER" "$MODEL")"
  PROVIDER="${PROVIDER_MODEL%% *}"
  MODEL="${PROVIDER_MODEL#* }"
else
  (( ${#ARGS[@]} <= 3 )) || { usage; die "too many args for raw model mode"; }
  (( ${#ARGS[@]} >= 2 )) || { usage; exit 2; }
  MODEL_SPEC="${ARGS[1]}"
  LABEL="${ARGS[2]:-}"
  PROVIDER_MODEL="$(parse_raw_model "$MODEL_SPEC")"
  PROVIDER="${PROVIDER_MODEL%% *}"
  MODEL="${PROVIDER_MODEL#* }"
fi

[[ -n "$THINKING_OVERRIDE" ]] && THINKING="$THINKING_OVERRIDE"
[[ -n "$TOOLS_OVERRIDE" ]] && TOOLS="$TOOLS_OVERRIDE"
[[ -n "$ROLE_OVERRIDE" ]] && ROLE="$ROLE_OVERRIDE"

PROMPTS_DIR="$DIR/../../../prompts/pi"
COMMON_SYSTEM_PROMPT="$PROMPTS_DIR/common-system.md"
ROLE_PROMPT="$PROMPTS_DIR/roles/$ROLE.md"
WORKER_CONTRACT_PROMPT="$PROMPTS_DIR/worker-contract.md"
[[ -f "$COMMON_SYSTEM_PROMPT" ]] || die "prompt not found: $COMMON_SYSTEM_PROMPT"
[[ -f "$ROLE_PROMPT" ]] || die "role prompt not found: $ROLE_PROMPT (role='$ROLE')"
[[ -f "$WORKER_CONTRACT_PROMPT" ]] || die "prompt not found: $WORKER_CONTRACT_PROMPT"
log "launching headless pi worker"
log "provider=$PROVIDER model=$MODEL thinking=$THINKING tools=$TOOLS role=$ROLE label=${LABEL:-}"

pid="$({
  cd "$WT"
  nohup pi -p --mode json -a \
    --provider "$PROVIDER" --model "$MODEL" --thinking "$THINKING" --tools "$TOOLS" \
    --append-system-prompt "$COMMON_SYSTEM_PROMPT" \
    --append-system-prompt "$ROLE_PROMPT" \
    --append-system-prompt "$WORKER_CONTRACT_PROMPT" \
    "@$WT/.task-spec.md" > "$WT/out.json" 2>&1 &
  echo $!
})"

printf '%s\n' "$pid"
