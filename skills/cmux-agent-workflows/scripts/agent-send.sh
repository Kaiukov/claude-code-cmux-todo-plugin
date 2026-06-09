#!/usr/bin/env bash
# Send a prompt to an agent surface and submit it (Enter).
# Use this instead of two separate `cmux send` + `send-key Enter` calls.
#
# Usage: agent-send.sh <surface> <text...>
#   agent-send.sh surface:169 "run bun test and paste the output"
# Reads text from stdin if only the surface is given (for long prompts):
#   agent-send.sh surface:169 < prompt.txt
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/lib.sh"

[[ $# -ge 1 ]] || die "usage: agent-send.sh <surface> <text...>   (or pipe text via stdin)"
SURFACE="$1"; shift
if [[ $# -gt 0 ]]; then TEXT="$*"; else TEXT="$(cat)"; fi
[[ -n "$TEXT" ]] || die "empty prompt"

# Send the body first, then Enter as a discrete key so multi-line text is not
# submitted line-by-line.
cmux send --surface "$SURFACE" -- "$TEXT" >&2
sleep 1
cmux send-key --surface "$SURFACE" "Enter" >&2
log "sent to $SURFACE (${#TEXT} chars)"
