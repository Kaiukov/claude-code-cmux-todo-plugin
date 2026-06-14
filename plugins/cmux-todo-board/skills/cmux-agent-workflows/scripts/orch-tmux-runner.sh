#!/usr/bin/env bash
# Launch a headless pi worker, watch it to completion, and maintain the
# orchestrator run-record consumed by orch-statusline.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<'EOF'
usage: orch-tmux-runner.sh --worktree <dir> --run-file <path> [--log-file <path>] [--profile <name> | --model <provider/model>] [--thinking <level>] [--tools <csv>] [--role <name>] [--label <text>]
EOF
}

RUN_FILE=""
LOG_FILE=""
WORKTREE=""
PROFILE=""
MODEL=""
THINKING=""
TOOLS=""
ROLE=""
LABEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-file) [[ $# -ge 2 ]] || { usage; exit 2; }; RUN_FILE="$2"; shift 2 ;;
    --run-file=*) RUN_FILE="${1#--run-file=}"; shift ;;
    --log-file) [[ $# -ge 2 ]] || { usage; exit 2; }; LOG_FILE="$2"; shift 2 ;;
    --log-file=*) LOG_FILE="${1#--log-file=}"; shift ;;
    --worktree) [[ $# -ge 2 ]] || { usage; exit 2; }; WORKTREE="$2"; shift 2 ;;
    --worktree=*) WORKTREE="${1#--worktree=}"; shift ;;
    --profile) [[ $# -ge 2 ]] || { usage; exit 2; }; PROFILE="$2"; shift 2 ;;
    --profile=*) PROFILE="${1#--profile=}"; shift ;;
    --model) [[ $# -ge 2 ]] || { usage; exit 2; }; MODEL="$2"; shift 2 ;;
    --model=*) MODEL="${1#--model=}"; shift ;;
    --thinking) [[ $# -ge 2 ]] || { usage; exit 2; }; THINKING="$2"; shift 2 ;;
    --thinking=*) THINKING="${1#--thinking=}"; shift ;;
    --tools) [[ $# -ge 2 ]] || { usage; exit 2; }; TOOLS="$2"; shift 2 ;;
    --tools=*) TOOLS="${1#--tools=}"; shift ;;
    --role) [[ $# -ge 2 ]] || { usage; exit 2; }; ROLE="$2"; shift 2 ;;
    --role=*) ROLE="${1#--role=}"; shift ;;
    --label) [[ $# -ge 2 ]] || { usage; exit 2; }; LABEL="$2"; shift 2 ;;
    --label=*) LABEL="${1#--label=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ -n "$RUN_FILE" && -n "$WORKTREE" ]] || { usage; exit 2; }
if [[ -n "$PROFILE" && -n "$MODEL" ]]; then
  echo "ERROR: use either --profile or --model, not both" >&2
  exit 2
fi
if [[ -z "$PROFILE" && -z "$MODEL" ]]; then
  echo "ERROR: missing --profile or --model" >&2
  exit 2
fi

WORKTREE="$(cd "$WORKTREE" && pwd)"
SPAWN_BIN="${ORCH_WORKER_SPAWN_BIN:-$DIR/worker-spawn.sh}"
WATCH_BIN="${ORCH_WORKER_WATCH_BIN:-$DIR/worker-watch.sh}"
OUT_FILE="$WORKTREE/out.json"
mkdir -p "$(dirname "$RUN_FILE")"
if [[ -n "$LOG_FILE" ]]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

update_run_file() {
  local tmp="${RUN_FILE}.tmp"
  jq "$@" "$RUN_FILE" > "$tmp"
  mv "$tmp" "$RUN_FILE"
}

spawn_args=("$WORKTREE")
if [[ -n "$PROFILE" ]]; then
  spawn_args+=(--profile "$PROFILE")
else
  spawn_args+=("$MODEL")
fi
[[ -n "$LABEL" ]] && spawn_args+=("$LABEL")
[[ -n "$THINKING" ]] && spawn_args+=(--thinking "$THINKING")
[[ -n "$TOOLS" ]] && spawn_args+=(--tools "$TOOLS")
[[ -n "$ROLE" ]] && spawn_args+=(--role "$ROLE")

pid="$("$SPAWN_BIN" "${spawn_args[@]}")"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
update_run_file --arg pid "$pid" --arg started "$started_at" --arg out "$OUT_FILE" '
  .pid = ($pid | tonumber) |
  .started_at = $started |
  .out_file = $out |
  .status = "running"
'

read_only=0
if [[ -z "$TOOLS" ]]; then
  read_only=1
else
  tools_csv=",${TOOLS// /},"
  if [[ "$tools_csv" != *",edit,"* && "$tools_csv" != *",write,"* ]]; then
    read_only=1
  fi
fi

watch_args=(--pid "$pid" --out "$OUT_FILE" --worktree "$WORKTREE")
(( read_only )) && watch_args+=(--read-only)

set +e
watch_output="$("$WATCH_BIN" "${watch_args[@]}" 2>&1)"
watch_rc=$?
set -e
printf '%s\n' "$watch_output"

status="crashed"
case "$watch_output" in
  *STATUS=DONE*) status="done" ;;
  *STATUS=KILLED_TIMEOUT*) status="killed_timeout" ;;
  *STATUS=KILLED_STALLED*) status="killed_stalled" ;;
esac
ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
head_sha="$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null || true)"
branch="$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
remote_ref="$(git -C "$WORKTREE" rev-parse "origin/$branch" 2>/dev/null || true)"

update_run_file \
  --arg status "$status" \
  --arg ended "$ended_at" \
  --argjson rc "$watch_rc" \
  --arg output "$watch_output" \
  --arg head_sha "$head_sha" \
  --arg remote_ref "$remote_ref" \
  --arg branch "$branch" '
    .status = $status |
    .ended_at = $ended |
    .watch_exit = $rc |
    .watch_output = $output |
    .branch = (if $branch == "" then .branch else $branch end) |
    .branch_name = (if $branch == "" then .branch_name else $branch end) |
    .head_sha = (if $head_sha == "" then .head_sha else $head_sha end) |
    .last_seen_head = (if $head_sha == "" then .last_seen_head else $head_sha end) |
    .last_seen_remote_ref = (if $remote_ref == "" then .last_seen_remote_ref else $remote_ref end)
  '

exit "$watch_rc"
