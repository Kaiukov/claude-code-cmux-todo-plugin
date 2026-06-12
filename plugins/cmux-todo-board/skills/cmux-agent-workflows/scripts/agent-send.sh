#!/usr/bin/env bash
# Send a prompt to an agent surface and submit it (Enter).
# Use this instead of two separate `cmux send` + `send-key Enter` calls.
#
# Usage: agent-send.sh [--kind pi] <surface> <text...>
#   agent-send.sh surface:169 "run bun test and paste the output"
#   agent-send.sh --kind pi surface:169 "run bun test and paste the output"
# Reads text from stdin if only the surface is given (for long prompts):
#   agent-send.sh surface:169 < prompt.txt
#
# When --kind is passed, waits for the agent to be ready before typing so a
# detached/quiet spawn never types into a still-booting TUI (#54).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/lib.sh"

AGENT_KIND=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kind) AGENT_KIND="$2"; shift 2 ;;
    --kind=*) AGENT_KIND="${1#--kind=}"; shift ;;
    --quiet) LOG_LEVEL=quiet; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) break ;;
  esac
done

[[ $# -ge 1 ]] || die "usage: agent-send.sh [--kind pi] <surface> <text...>   (or pipe text via stdin)"
SURFACE="$1"; shift
if [[ $# -gt 0 ]]; then TEXT="$*"; else TEXT="$(cat)"; fi
[[ -n "$TEXT" ]] || die "empty prompt"

# Wait for agent readiness when kind is known, so prompts never land in a
# still-booting TUI (#54). Uses a short timeout since the agent should already
# be up (agent-spawn blocks until ready).
if [[ -n "$AGENT_KIND" ]]; then
  agent_kind_supported "$AGENT_KIND" || die "unknown --kind: $AGENT_KIND  (supported: ${AGENT_KINDS[*]})"
  if wait_agent_ready "$SURFACE" "$AGENT_KIND" 30; then
    log "agent ready in $SURFACE"
  else
    log "WARNING: agent not confirmed ready after 30s in $SURFACE — sending anyway"
  fi
fi

# Send the body first, then Enter as a discrete key so multi-line text is not
# submitted line-by-line.
cmux send --surface "$SURFACE" -- "$TEXT" >&2
sleep 1
cmux send-key --surface "$SURFACE" "Enter" >&2
log "sent to $SURFACE (${#TEXT} chars)"
