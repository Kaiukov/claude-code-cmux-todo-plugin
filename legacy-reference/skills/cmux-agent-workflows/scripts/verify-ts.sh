#!/usr/bin/env bash
# Orchestrator hard gate for the TS adapter: typecheck + full test suite.
# Run this yourself on the agent's worktree BEFORE merging — never trust the
# agent's self-report. Exits non-zero if typecheck has errors or any test fails.
#
# Usage: verify-ts.sh <worktree-or-portfolio-ts-path>
#   verify-ts.sh /Users/x/Code/mpc-108
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/lib.sh"

[[ $# -ge 1 ]] || die "usage: verify-ts.sh <worktree-or-portfolio-ts-path>"
P="$1"
[[ -f "$P/package.json" ]] || P="$P/portfolio-ts"
[[ -f "$P/package.json" ]] || die "no portfolio-ts/package.json under $1"
cd "$P"

echo "=== TYPECHECK ($P) ==="
if bun run typecheck; then tc=0; else tc=1; fi

echo "=== TEST ($P) ==="
test_out="$(bun test 2>&1)" || true
echo "$test_out" | tail -8

fails="$(echo "$test_out" | grep -Eo '[0-9]+ fail' | awk '{print $1}' | tail -1 || echo 0)"
fails="${fails:-0}"

echo "=== GATE ==="
if [[ "$tc" -eq 0 && "$fails" -eq 0 ]]; then
  echo "PASS — typecheck clean, 0 test failures"
  exit 0
else
  echo "FAIL — typecheck=$tc, test failures=$fails"
  exit 1
fi
