#!/usr/bin/env bash
# Audit open cmux surface panes: classify each as active/candidate/protected,
# then (with --apply) tear down idle/finished agent surfaces to reclaim slots.
#
# Usage: agent-audit.sh [--apply]
#   agent-audit.sh           # dry-run: print what WOULD be closed
#   agent-audit.sh --apply   # actually close candidate surfaces
#
# Hard safety — NEVER closes:
#   - the orchestrator's own surface ($CMUX_SURFACE_ID)
#   - the currently [focused] surface
#   - any browser surface
#   - anything not matching the agent naming/process signature
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/lib.sh"

APPLY=""
while (( $# > 0 )); do
  case "$1" in
    --apply) APPLY=1; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) die "unknown arg: $1  (expected: --apply)" ;;
  esac
done

if ! command -v cmux &>/dev/null; then
  die "cmux not found on PATH"
fi

# ─── classification helpers ────────────────────────────────────────────────

# True if surface ref matches the orchestrator's own surface ID.
is_own_surface() {
  local ref="$1"
  [[ -n "${CMUX_SURFACE_ID:-}" && "$ref" == "$CMUX_SURFACE_ID" ]]
}

# True if the cmux list-panels line represents a focused surface.
is_focused_line() {
  local line="$1"
  [[ "$line" == *"[focused]"* ]]
}

# True if the cmux list-panels line represents a browser surface.
is_browser_line() {
  local line="$1"
  # Lines look like: "  surface:120  browser  \"...\""
  [[ "$line" =~ ^[[:space:]*]*surface:[0-9]+[[:space:]]+browser ]]
}

# True if the title portion of a line matches a band from BAND_POOL.
# Agent-spawn.sh always names panes with a band, optionally followed by a label
# (e.g. "Aerosmith" or "Asia L4").
has_agent_naming() {
  local title="$1"
  for band in "${BAND_POOL[@]}"; do
    if [[ "$title" == "$band"* ]]; then
      return 0
    fi
  done
  return 1
}

# True if an agent process (pi) is running in the given tty.
agent_process_running() {
  local tty="$1"
  local pattern pids
  pattern="$(agent_kill_pattern "")"
  pids="$(ps -t "$tty" -o pid=,comm= 2>/dev/null | grep -Ei "$pattern" | awk '{print $1}' || true)"
  [[ -n "$pids" ]]
}

# ─── parse cmux list-panels ────────────────────────────────────────────────

PANELS="$(cmux list-panels 2>/dev/null || true)"
if [[ -z "$PANELS" ]]; then
  log "no surfaces found (cmux list-panels returned empty)"
  exit 0
fi

declare -a CANDIDATES=()
declare -a ACTIVE_AGENTS=()
declare -a PROTECTED=()
declare -a ERRORS=()

log "auditing surfaces (${APPLY:+--apply}${APPLY:-(dry-run)})"
if [[ -n "${CMUX_SURFACE_ID:-}" ]]; then
  log "orchestrator surface: $CMUX_SURFACE_ID"
fi

while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  # Extract surface ref: "surface:NNN"
  ref="$(echo "$line" | sed -n 's/.*\(surface:[0-9]\{1,\}\).*/\1/p')"
  [[ -z "$ref" ]] && continue

  # Extract title from the last quoted string
  title="$(echo "$line" | sed -n 's/.*"\([^"]*\)"[[:space:]]*$/\1/p')"
  [[ -z "$title" ]] && title=""

  # ─── protection guards ─────────────────────────────────────────────────

  if is_own_surface "$ref"; then
    log "protected  $ref  (orchestrator own surface)"
    PROTECTED+=("$ref")
    continue
  fi

  if is_focused_line "$line"; then
    log "protected  $ref  (focused)"
    PROTECTED+=("$ref")
    continue
  fi

  if is_browser_line "$line"; then
    log "protected  $ref  (browser)"
    PROTECTED+=("$ref")
    continue
  fi

  # ─── agent pane detection ──────────────────────────────────────────────

  # Check agent naming signature: title must start with a band name.
  if ! has_agent_naming "$title"; then
    log "skip       $ref  (not an agent pane: \"$title\")"
    continue
  fi

  # Resolve tty and check for running agent process.
  tty="$(cmux_tty "$ref" 2>/dev/null || true)"
  if [[ -z "$tty" ]]; then
    log "candidate  $ref  \"$title\"  (no tty — pane already gone?)"
    CANDIDATES+=("$ref")
    continue
  fi

  if agent_process_running "$tty"; then
    log "active     $ref  \"$title\"  (/dev/$tty has agent process)"
    ACTIVE_AGENTS+=("$ref")
  else
    log "candidate  $ref  \"$title\"  (/dev/$tty idle — no agent process)"
    CANDIDATES+=("$ref")
  fi

done <<< "$PANELS"

# ─── summary ────────────────────────────────────────────────────────────────

echo ""
log "=== audit summary ==="
log "protected:     ${#PROTECTED[@]}  ($(IFS=' '; echo "${PROTECTED[*]:-none}"))"
log "active agents: ${#ACTIVE_AGENTS[@]}  ($(IFS=' '; echo "${ACTIVE_AGENTS[*]:-none}"))"
log "candidates:    ${#CANDIDATES[@]}  ($(IFS=' '; echo "${CANDIDATES[*]:-none}"))"

if (( ${#CANDIDATES[@]} == 0 )); then
  log "nothing to reclaim"
  exit 0
fi

# ─── teardown ───────────────────────────────────────────────────────────────

if [[ -z "$APPLY" ]]; then
  log "DRY-RUN: run with --apply to close ${#CANDIDATES[@]} candidate surface(s)"
  exit 0
fi

log "tearing down ${#CANDIDATES[@]} candidate surface(s)..."

for ref in "${CANDIDATES[@]}"; do
  log "closing $ref"

  # Kill any stray process first, reusing agent-kill.sh semantics.
  tty="$(cmux_tty "$ref" 2>/dev/null || true)"
  if [[ -n "$tty" ]]; then
    pattern="$(agent_kill_pattern "")"
    pids="$(ps -t "$tty" -o pid=,comm= 2>/dev/null | grep -Ei "$pattern" | awk '{print $1}' || true)"
    if [[ -n "$pids" ]]; then
      log "  killing stray procs in $ref: $pids"
      # shellcheck disable=SC2086
      kill $pids 2>/dev/null || true
      sleep 2
      # shellcheck disable=SC2086
      kill -9 $pids 2>/dev/null || true
    fi
  fi

  cmux close-surface --surface "$ref" >&2 || {
    log "  WARNING: close-surface failed for $ref (already gone?)"
    ERRORS+=("$ref")
    continue
  }
  log "  closed $ref"
done

if (( ${#ERRORS[@]} > 0 )); then
  log "WARNING: ${#ERRORS[@]} surface(s) had errors during teardown: ${ERRORS[*]}"
fi

log "audit complete"
