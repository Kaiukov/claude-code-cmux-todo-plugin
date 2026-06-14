#!/usr/bin/env bash
# spawn-3x3.sh — splits the CURRENT cmux workspace into a 3×3 pane grid
# Usage: ./spawn-3x3.sh
set -euo pipefail

CMUX="${CMUX:-cmux}"

# Detect current workspace & surface — always normalize via identify to get short refs
CTX=$("$CMUX" identify --json 2>&1)
WS=$(echo "$CTX" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['caller']['workspace_ref'])")
SURF=$(echo "$CTX" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['caller']['surface_ref'])")

echo "→ Splitting current workspace ($WS) into 3×3 grid..."
echo "  caller surface: $SURF"

# Close all other surfaces so only caller remains
PANES=$("$CMUX" list-panes --workspace "$WS" --json 2>&1)
for surf in $(echo "$PANES" | python3 -c "
import json, sys
for p in json.load(sys.stdin)['panes']:
    for s in p['surface_refs']:
        print(s)
"); do
  if [[ "$surf" != "$SURF" ]]; then
    "$CMUX" close-surface --workspace "$WS" --surface "$surf" 2>/dev/null || true
  fi
done
echo "  cleaned up old panes"

# Row 0: split right twice → 3 columns (starting from caller surface)
TOP_LEFT="$SURF"
TOP_MID=$("$CMUX" new-split right --workspace "$WS" --surface "$TOP_LEFT" --focus false 2>&1 | grep -oE 'surface:[0-9]+')
echo "  top-mid  surface: $TOP_MID"

TOP_RIGHT=$("$CMUX" new-split right --workspace "$WS" --surface "$TOP_MID" --focus false 2>&1 | grep -oE 'surface:[0-9]+')
echo "  top-right surface: $TOP_RIGHT"

# Row 1: split down on each top surface
MID_LEFT=$("$CMUX" new-split down --workspace "$WS" --surface "$TOP_LEFT" --focus false 2>&1 | grep -oE 'surface:[0-9]+')
echo "  mid-left  surface: $MID_LEFT"

MID_MID=$("$CMUX" new-split down --workspace "$WS" --surface "$TOP_MID" --focus false 2>&1 | grep -oE 'surface:[0-9]+')
echo "  mid-mid   surface: $MID_MID"

MID_RIGHT=$("$CMUX" new-split down --workspace "$WS" --surface "$TOP_RIGHT" --focus false 2>&1 | grep -oE 'surface:[0-9]+')
echo "  mid-right surface: $MID_RIGHT"

# Row 2: split down on each mid surface
BOT_LEFT=$("$CMUX" new-split down --workspace "$WS" --surface "$MID_LEFT" --focus false 2>&1 | grep -oE 'surface:[0-9]+')
echo "  bot-left  surface: $BOT_LEFT"

BOT_MID=$("$CMUX" new-split down --workspace "$WS" --surface "$MID_MID" --focus false 2>&1 | grep -oE 'surface:[0-9]+')
echo "  bot-mid   surface: $BOT_MID"

BOT_RIGHT=$("$CMUX" new-split down --workspace "$WS" --surface "$MID_RIGHT" --focus false 2>&1 | grep -oE 'surface:[0-9]+')
echo "  bot-right surface: $BOT_RIGHT"

echo "✓ 3×3 grid ready in $WS"
echo "  Layout:"
echo "  $TOP_LEFT  | $TOP_MID  | $TOP_RIGHT"
echo "  $MID_LEFT  | $MID_MID  | $MID_RIGHT"
echo "  $BOT_LEFT  | $BOT_MID  | $BOT_RIGHT"
