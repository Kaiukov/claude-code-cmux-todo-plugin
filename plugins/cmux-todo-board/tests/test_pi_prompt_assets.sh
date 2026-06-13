#!/usr/bin/env bash
# Test: Pi worker prompt assets exist, are well-formed, and are wired correctly.
#   bash plugins/cmux-todo-board/tests/test_pi_prompt_assets.sh
set -euo pipefail

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="$SCRIPT_DIR/../prompts/pi"
SPAWN_SCRIPT="$SCRIPT_DIR/../skills/cmux-agent-workflows/scripts/agent-spawn.sh"

# ─── Asset existence and non-empty ─────────────────────────────────────
ASSETS=(
  "$PROMPTS_DIR/common-system.md"
  "$PROMPTS_DIR/roles/backend.md"
  "$PROMPTS_DIR/roles/frontend.md"
  "$PROMPTS_DIR/roles/frontend-top.md"
  "$PROMPTS_DIR/roles/review.md"
  "$PROMPTS_DIR/roles/docs.md"
)

for f in "${ASSETS[@]}"; do
  if [[ -f "$f" ]]; then
    pass "file exists: $f"
  else
    fail "file missing: $f"
  fi
  if [[ -s "$f" ]]; then
    pass "file non-empty: $f"
  else
    fail "file empty: $f"
  fi
done

# ─── common-system.md length cap ───────────────────────────────────────
LINES=$(wc -l < "$PROMPTS_DIR/common-system.md" | tr -d ' ')
if (( LINES <= 60 )); then
  pass "common-system.md line count ($LINES) <= 60"
else
  fail "common-system.md line count ($LINES) exceeds 60"
fi

# ─── Layer separation: common-system.md must NOT contain role words ────
COMMON_CONTENT=$(<"$PROMPTS_DIR/common-system.md")
if ! echo "$COMMON_CONTENT" | grep -qi "React"; then
  pass "common-system.md does not contain 'React'"
else
  fail "common-system.md contains 'React' (layer separation violation)"
fi
if ! echo "$COMMON_CONTENT" | grep -qi "CHANGELOG"; then
  pass "common-system.md does not contain 'CHANGELOG'"
else
  fail "common-system.md contains 'CHANGELOG' (layer separation violation)"
fi

# ─── review.md enforces read-only wording ──────────────────────────────
REVIEW_CONTENT=$(<"$PROMPTS_DIR/roles/review.md")
if echo "$REVIEW_CONTENT" | grep -qi "READ-ONLY\|must not modify\|do not write"; then
  pass "review.md asserts read-only policy"
else
  fail "review.md missing read-only wording"
fi

# ─── agent-spawn.sh wires --append-system-prompt for pi kind ───────────
if [[ -f "$SPAWN_SCRIPT" ]]; then
  SPAWN_CONTENT=$(<"$SPAWN_SCRIPT")

  # Check the guard markers exist
  if echo "$SPAWN_CONTENT" | grep -qF '# --- #118 prompt layering ---'; then
    pass "agent-spawn.sh has #118 start marker"
  else
    fail "agent-spawn.sh missing #118 start marker"
  fi
  if echo "$SPAWN_CONTENT" | grep -qF '# --- end #118 ---'; then
    pass "agent-spawn.sh has #118 end marker"
  else
    fail "agent-spawn.sh missing #118 end marker"
  fi

  # Check --append-system-prompt for common-system.md
  if echo "$SPAWN_CONTENT" | grep -qF -- '--append-system-prompt' && \
     echo "$SPAWN_CONTENT" | grep -qF 'common-system.md'; then
    pass "agent-spawn.sh appends common-system.md via --append-system-prompt"
  else
    fail "agent-spawn.sh missing --append-system-prompt for common-system.md"
  fi

  # Check --append-system-prompt for a role file
  if echo "$SPAWN_CONTENT" | grep -qF -- '--append-system-prompt' && \
     echo "$SPAWN_CONTENT" | grep -qF 'roles/'; then
    pass "agent-spawn.sh appends role file via --append-system-prompt"
  else
    fail "agent-spawn.sh missing --append-system-prompt for role file"
  fi

  # Check the block is guarded for pi kind
  if echo "$SPAWN_CONTENT" | grep -qF 'AGENT_KIND' && \
     echo "$SPAWN_CONTENT" | grep -qF '"pi"'; then
    pass "agent-spawn.sh #118 block guarded for pi kind"
  else
    fail "agent-spawn.sh #118 block not guarded for pi kind"
  fi
else
  fail "agent-spawn.sh not found at $SPAWN_SCRIPT"
fi

# ─── Summary ───────────────────────────────────────────────────────────
echo "---"
echo "Total: PASS=$PASS FAIL=$FAIL"

if (( FAIL > 0 )); then
  exit 1
fi
