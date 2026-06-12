#!/usr/bin/env bash
# coms-net-await.sh — Block until a `done` event arrives on a coms-net channel.
#
# Ported from disler/pi-vs-claude-code (MIT).
# https://github.com/disler/pi-vs-claude-code
#
# Usage: coms-net-await.sh [--channel <key>] [--timeout <sec>] [--hub <url>]
#
# Blocks until a `type:"done"` event arrives on the given channel.  Prints
# the event JSON to stdout and exits 0.  On timeout or when the hub is
# unreachable, exits non-zero so the caller falls back to git-poll.
#
# Env:
#   COMS_NET_TOKEN   — shared auth token (required)
#   COMS_NET_CHANNEL — default channel if --channel not given (falls back to $PWD)
#   COMS_NET_HUB_URL — default hub URL (default http://127.0.0.1:9876)
set -euo pipefail

CHANNEL="${COMS_NET_CHANNEL:-$PWD}"
TIMEOUT_SEC=120
HUB_URL="${COMS_NET_HUB_URL:-http://127.0.0.1:9876}"
TOKEN="${COMS_NET_TOKEN:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="$2"; shift 2 ;;
    --timeout) TIMEOUT_SEC="$2"; shift 2 ;;
    --hub)     HUB_URL="$2"; shift 2 ;;
    --token)   TOKEN="$2"; shift 2 ;;
    *)         shift ;;
  esac
done

if [[ -z "$TOKEN" ]]; then
  echo '{"error":"COMS_NET_TOKEN not set"}' >&2
  exit 2
fi

# Convert timeout to milliseconds for the hub
TIMEOUT_MS=$((TIMEOUT_SEC * 1000))

# ── Health check: if hub is unreachable, exit non-zero immediately ─────
RESP=""
RESP=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${TOKEN}" \
  --max-time 5 \
  "${HUB_URL}/health" 2>/dev/null) || true

if [[ "$RESP" != "200" ]]; then
  echo "coms-net-await: hub unreachable (health check returned ${RESP:-<no response>}), triggering git-poll fallback" >&2
  exit 3
fi

# ── Await the event (poll mode — curl-friendly, no SSE needed in bash) ──
RESULT=""
RESULT=$(curl -s -f \
  -H "Authorization: Bearer ${TOKEN}" \
  --max-time $((TIMEOUT_SEC + 10)) \
  "${HUB_URL}/await?channel=$(printf '%s' "$CHANNEL" | python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read()))" 2>/dev/null || printf '%s' "$CHANNEL" | perl -MURI::Escape -lne 'print uri_escape($_)' 2>/dev/null || printf '%s' "$CHANNEL")&type=done&timeout=${TIMEOUT_MS}&poll=1" 2>/dev/null) || true

if [[ -z "$RESULT" ]]; then
  echo "coms-net-await: timeout or no response from hub, triggering git-poll fallback" >&2
  exit 4
fi

# Validate we got a JSON object with a type field
if ! echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d,dict); assert 'type' in d" 2>/dev/null; then
  if ! echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin)" 2>/dev/null; then
    echo "coms-net-await: invalid JSON response, triggering git-poll fallback" >&2
    exit 5
  fi
fi

echo "$RESULT"
exit 0
