#!/usr/bin/env bash
# Tests for reflow-tolerant agent readiness probe (#54).
# Verifies that stripping ALL whitespace + box-drawing chars and matching
# command-bar tokens (anything|agents|commands) correctly detects the opencode
# TUI even when it renders as multi-column boxes in very narrow split panes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_FILE="$REPO_ROOT/skills/cmux-agent-workflows/scripts/lib.sh"
FIXTURE="$SCRIPT_DIR/fixtures/opencode-narrow-pane-footer.txt"

if [[ ! -f "$LIB_FILE" ]]; then
  echo "FAIL: lib.sh not found at $LIB_FILE"
  exit 1
fi
if [[ ! -f "$FIXTURE" ]]; then
  echo "FAIL: fixture not found at $FIXTURE"
  exit 1
fi

source "$LIB_FILE"

failures=0

# Simulate the wait_agent_ready normalization logic
# opencode: aggressive strip of whitespace + box-drawing chars
# codex: collapse whitespace only (tr -s)
normalize_screen() {
  local screen="$1" kind="${2:-opencode}"
  if [[ "$kind" == "opencode" ]]; then
    printf '%s' "$screen" | tr -d '[:space:]┃┏┓┗┛━╹▀│─┌┐└┘●'
  else
    printf '%s' "$screen" | tr -s ' \n' ' '
  fi
}

# ── Test 1: Real narrow-pane fixture — NEW pattern accepts ──
echo "=== Test 1: Narrow-pane fixture ACCEPTED by new pattern ==="
fixture="$(cat "$FIXTURE")"
normalized="$(normalize_screen "$fixture")"
new_pattern="$(agent_ready_patterns opencode)"
if grep -qE "$new_pattern" <<<"$normalized"; then
  echo "PASS"
else
  echo "FAIL: new pattern should accept narrow-pane fixture"
  failures=$((failures + 1))
fi

# ── Test 2: Real narrow-pane fixture — OLD pattern REJECTS ──
echo "=== Test 2: Narrow-pane fixture REJECTED by old pattern ==="
old_pattern='Build · |· DeepSeek|· GPT|^OpenCode|esc dismiss'
if grep -qE "$old_pattern" <<<"$normalized"; then
  echo "FAIL: old pattern should reject narrow-pane fixture (model banner is column-interleaved)"
  failures=$((failures + 1))
else
  echo "PASS"
fi

# ── Test 3: Normal (wide, non-reflowed) footer — NEW pattern accepts ──
echo "=== Test 3: Normal footer accepted ==="
normal_screen='any command here   anything   agents  commands  esc dismiss'
normal_norm="$(normalize_screen "$normal_screen")"
if grep -qE "$new_pattern" <<<"$normal_norm"; then
  echo "PASS"
else
  echo "FAIL: normal footer should match new pattern"
  failures=$((failures + 1))
fi

# ── Test 4: Bare opencode splash — NEW pattern REJECTS (no false positive) ──
echo "=== Test 4: Bare splash without command bar rejected ==="
splash_screen='Welcome to OpenCode! Type your prompt below.'
splash_norm="$(normalize_screen "$splash_screen")"
if grep -qE "$new_pattern" <<<"$splash_norm"; then
  echo "FAIL: bare splash should not match (no anything/agents/commands)"
  failures=$((failures + 1))
else
  echo "PASS"
fi

# ── Test 5: codex patterns still work (collapse normalization) ──
echo "=== Test 5: codex readiness patterns ==="
codex_screen='OpenAI Codex  gpt-5-codex medium'
codex_norm="$(normalize_screen "$codex_screen" codex)"
codex_pattern="$(agent_ready_patterns codex)"
if grep -qE "$codex_pattern" <<<"$codex_norm"; then
  echo "PASS"
else
  echo "FAIL: codex patterns should match"
  failures=$((failures + 1))
fi

# ── Test 6: agents token alone (narrow pane, only command bar visible) ──
echo "=== Test 6: agents token alone ==="
agents_only='  agents  '
agents_norm="$(normalize_screen "$agents_only")"
if grep -qE "$new_pattern" <<<"$agents_norm"; then
  echo "PASS"
else
  echo "FAIL: agents token alone should match"
  failures=$((failures + 1))
fi

# ── Test 7: Previous v1 fix (tr -s collapse) would ALSO fail on fixture ──
echo "=== Test 7: Previous tr -s fix fails on narrow-pane fixture ==="
prev_normalized="$(printf '%s' "$fixture" | tr -s ' \n' ' ')"
if grep -qE "$old_pattern" <<<"$prev_normalized"; then
  echo "FAIL: previous tr -s fix should NOT rescue old pattern on multi-column fixture"
  failures=$((failures + 1))
else
  echo "PASS"
fi

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All agent readiness probe tests passed."
else
  echo "$failures test(s) failed."
  exit 1
fi
