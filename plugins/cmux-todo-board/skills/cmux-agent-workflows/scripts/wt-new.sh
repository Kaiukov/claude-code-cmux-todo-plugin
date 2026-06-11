#!/usr/bin/env bash
# Create an isolated git worktree for an agent task.
# By default branches off origin/main; override via BASE_REF env.
# Copies .env / .env.local only if present; never fails if absent.
# Runs `bun install` only if a package.json exists in the worktree root.
#
# Usage: wt-new.sh <branch> <dir-name> [repo-root]
#   BASE_REF=origin/dev wt-new.sh feat/foo ../wt-feat-foo
# Echoes the absolute worktree path on success.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/lib.sh"

[[ $# -ge 2 ]] || die "usage: wt-new.sh <branch> <dir-name> [repo-root]"
BRANCH="$1"; NAME="$2"
REPO="${3:-$(git rev-parse --show-toplevel)}"
WT="$(dirname "$REPO")/$NAME"
BASE_REF="${BASE_REF:-origin/main}"

[[ -e "$WT" ]] && die "worktree path already exists: $WT"

log "fetching $BASE_REF"
git -C "$REPO" fetch -q "${BASE_REF%/*}" "${BASE_REF#*/}" 2>/dev/null || \
  git -C "$REPO" fetch -q origin
log "creating worktree $WT (branch $BRANCH off $BASE_REF)"
git -C "$REPO" worktree add -b "$BRANCH" "$WT" "$BASE_REF" >&2

# Carry over env files (gitignored, not in worktree by default).
# Only copy what exists — never fail if absent.
for f in .env .env.local; do
  [[ -f "$REPO/$f" ]] && cp "$REPO/$f" "$WT/$f" && log "copied $f"
done

# node_modules is not inherited; install deps only if the project uses them.
if [[ -f "$WT/package.json" ]]; then
  if command -v bun &>/dev/null; then
    log "bun install (this takes a moment)"
    ( cd "$WT" && bun install >&2 )
  elif command -v npm &>/dev/null; then
    log "npm install (this takes a moment)"
    ( cd "$WT" && npm install >&2 )
  fi
fi

log "ready"
echo "$WT"
