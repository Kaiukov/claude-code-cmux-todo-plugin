#!/usr/bin/env bash
# Project-agnostic verification gate for agent worktrees.
# - Runs `bash -n` on changed shell scripts (vs base ref).
# - Runs `bun test` / `npm test` only if package.json has a test script.
# - No-op success when there is nothing to verify.
#
# Usage: verify.sh <worktree-path> [base-ref]
#   verify.sh /Users/x/Code/wt-feat-foo
#   verify.sh /Users/x/Code/wt-feat-foo origin/dev
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/lib.sh"

[[ $# -ge 1 ]] || die "usage: verify.sh <worktree-path> [base-ref]"
WT="$1"
BASE="${2:-origin/main}"
[[ -d "$WT" ]] || die "worktree not found: $WT"

# Resolve the main repo root from the worktree metadata.
REPO="$(git -C "$WT" rev-parse --show-toplevel 2>/dev/null)" || die "not a git repo: $WT"

ANY_CHECKS=0
FAILED=0

# --- Shell syntax check -------------------------------------------------
SHELL_FILES="$(git -C "$REPO" diff --name-only "$BASE" --diff-filter=ACMRT -- "$WT" 2>/dev/null | grep -E '\.sh$' || true)"
if [[ -n "$SHELL_FILES" ]]; then
  ANY_CHECKS=1
  echo "=== SHELL SYNTAX ($(echo "$SHELL_FILES" | wc -l | tr -d ' ') files) ==="
  while IFS= read -r f; do
    # The diff lists paths relative to REPO; resolve them.
    ffull="$REPO/$f"
    if bash -n "$ffull" 2>&1; then
      echo "  OK  $f"
    else
      echo "  FAIL $f"
      FAILED=1
    fi
  done <<<"$SHELL_FILES"
fi

# --- Test suite (bun/npm) ------------------------------------------------
if [[ -f "$WT/package.json" ]]; then
  TEST_SCRIPT=$(jq -r '.scripts.test // empty' "$WT/package.json" 2>/dev/null || true)
  if [[ -n "$TEST_SCRIPT" ]]; then
    ANY_CHECKS=1
    echo "=== TEST ($WT) ==="
    if command -v bun &>/dev/null && grep -q '"bun"' "$WT/package.json" 2>/dev/null; then
      ( cd "$WT" && bun test ) || FAILED=1
    elif command -v npm &>/dev/null; then
      ( cd "$WT" && npm test ) || FAILED=1
    else
      log "package.json has a test script but neither bun nor npm found"
      FAILED=1
    fi
  fi
fi

# --- GATE ----------------------------------------------------------------
if [[ "$ANY_CHECKS" -eq 0 ]]; then
  echo "=== GATE: no-op (nothing to verify) ==="
  exit 0
elif [[ "$FAILED" -eq 0 ]]; then
  echo "=== GATE: PASS ==="
  exit 0
else
  echo "=== GATE: FAIL ==="
  exit 1
fi
