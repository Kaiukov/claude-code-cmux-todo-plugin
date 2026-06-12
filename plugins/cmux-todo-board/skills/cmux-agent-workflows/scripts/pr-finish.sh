#!/usr/bin/env bash
# Squash-merge a PR and clean up its worktree. Run AFTER verify-ts.sh passes.
# The local-branch delete failing while a worktree is checked out is harmless —
# this script removes the worktree first to avoid that noise.
#
# Usage: pr-finish.sh <pr-number> [worktree-path]
#   pr-finish.sh 121 /Users/x/Code/mpc-107
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/lib.sh"

[[ $# -ge 1 ]] || die "usage: pr-finish.sh <pr-number> [worktree-path]"
PR="$1"; WT="${2:-}"

# Resolve the main repo root and cd there FIRST — otherwise removing the
# worktree we're standing in invalidates cwd and the merge step fails with
# "Unable to read current working directory".
MAIN_ROOT="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
[[ -n "$MAIN_ROOT" && -d "$MAIN_ROOT" ]] && cd "$MAIN_ROOT"

if [[ -n "$WT" && -d "$WT" ]]; then
  log "removing worktree $WT (so branch delete is clean)"
  git worktree remove "$WT" --force || true
  git worktree prune
fi

printf 'Merge PR #%s? (y/N) ' "$PR"
read -r RESPONSE || RESPONSE=""
case "$(printf '%s' "$RESPONSE" | tr '[:upper:]' '[:lower:]')" in
  y|yes) ;;
  *) die "merge aborted by user" ;;
esac

log "squash-merging PR #$PR"
gh pr merge "$PR" --squash --delete-branch

log "merged. main is now:"
git fetch -q origin main
git log --oneline origin/main -1
