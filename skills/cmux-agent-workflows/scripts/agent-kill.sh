#!/usr/bin/env bash
# Stop the agent process running in a surface, then optionally close the split.
# Resolves the surface's tty from `cmux tree --json` and kills its foreground procs.
#
# Usage: agent-kill.sh <surface> [--agent opencode|codex] [--close]
#   agent-kill.sh surface:169 --close
#   agent-kill.sh surface:169 --agent codex --close
#
# `--agent` narrows the ps-grep pattern to the specific binary tree. If
# omitted, the broadest pattern is used (matches opencode + codex + helpers).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/lib.sh"

AGENT_KIND=""
CLOSE=""
SURFACE=""
while (( $# > 0 )); do
  case "$1" in
    --agent) AGENT_KIND="$2"; shift 2 ;;
    --agent=*) AGENT_KIND="${1#--agent=}"; shift ;;
    --close) CLOSE="--close"; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    surface:*)
      [[ -z "$SURFACE" ]] || die "surface specified twice"
      SURFACE="$1"; shift ;;
    *)
      die "unknown arg: $1  (expected: <surface> [--agent opencode|codex] [--close])" ;;
  esac
done
[[ -n "$SURFACE" ]] || die "usage: agent-kill.sh <surface> [--agent opencode|codex] [--close]"

if [[ -n "$AGENT_KIND" ]]; then
  agent_kind_supported "$AGENT_KIND" || die "unknown --agent: $AGENT_KIND"
fi

TTY="$(cmux_tty "$SURFACE")"
[[ -n "$TTY" ]] || die "no tty for $SURFACE (already gone?)"
log "surface $SURFACE -> /dev/$TTY"

PATTERN="$(agent_kill_pattern "$AGENT_KIND")"
PIDS="$(ps -t "$TTY" -o pid=,comm= | grep -Ei "$PATTERN" | awk '{print $1}' || true)"
if [[ -n "$PIDS" ]]; then
  log "killing: $PIDS  (pattern: $PATTERN)"
  # shellcheck disable=SC2086
  kill $PIDS 2>/dev/null || true
  sleep 2
  # shellcheck disable=SC2086
  kill -9 $PIDS 2>/dev/null || true
else
  log "no agent process found on $TTY (pattern: $PATTERN)"
fi

if [[ "$CLOSE" == "--close" ]]; then
  log "closing surface $SURFACE"
  cmux close-surface --surface "$SURFACE" >&2 || true
fi
log "done"
