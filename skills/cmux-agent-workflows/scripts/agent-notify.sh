#!/usr/bin/env bash
# Agent's FINAL step: signal completion to the orchestrator via cmux notify
# (PRIMARY) or stdout (FALLBACK — still captured by poller/log). Never hard-fail.
#
# Usage: agent-notify.sh --task <id> --surface <ref> --status success|failure [--branch <b>]
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/lib.sh"

format_notify_payload() {
  local task="$1" surface="$2" status="$3" branch="${4:-}"
  if [[ -n "$branch" ]]; then
    echo "CTB-DONE task=${task} surface=${surface} status=${status} branch=${branch}"
  else
    echo "CTB-DONE task=${task} surface=${surface} status=${status}"
  fi
}

TASK=""; SURFACE=""; STATUS=""; BRANCH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)    TASK="$2"; shift 2 ;;
    --surface) SURFACE="$2"; shift 2 ;;
    --status)  STATUS="$2"; shift 2 ;;
    --branch)  BRANCH="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$TASK" || -z "$SURFACE" || -z "$STATUS" ]]; then
  die "usage: agent-notify.sh --task <id> --surface <ref> --status success|failure [--branch <b>]"
fi

PAYLOAD="$(format_notify_payload "$TASK" "$SURFACE" "$STATUS" "$BRANCH")"

if command -v cmux &>/dev/null; then
  cmux notify "$PAYLOAD" 2>/dev/null || true
  echo "$PAYLOAD"
else
  echo "$PAYLOAD"
fi
