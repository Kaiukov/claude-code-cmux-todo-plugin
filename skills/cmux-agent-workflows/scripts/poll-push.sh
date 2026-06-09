#!/usr/bin/env bash
# Poll origin until a branch is pushed or updated past a baseline.
# Designed to run with Bash run_in_background:true so the orchestrator is
# notified when an agent finishes and pushes — no manual re-checking.
#
# Usage: poll-push.sh <branch> [interval-sec] [timeout-sec] [repo-root]
#   poll-push.sh feat/cf-108 30 1800
# Prints "PUSHED <sha>" and the PR (if any) when it detects a new/changed tip.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/lib.sh"

[[ $# -ge 1 ]] || die "usage: poll-push.sh <branch> [interval] [timeout] [repo-root]"
BRANCH="$1"; INTERVAL="${2:-30}"; TIMEOUT="${3:-1800}"; REPO="${4:-$(git rev-parse --show-toplevel)}"

baseline="$(git -C "$REPO" ls-remote origin "$BRANCH" | awk '{print $1}')"
log "baseline for $BRANCH: ${baseline:-<none>}"

# If branch already exists on origin and has commits ahead of origin/main,
# report done immediately — don't wait for a SHA change that will never come.
if [[ -n "$baseline" ]]; then
  git -C "$REPO" fetch origin "$BRANCH" main --quiet 2>/dev/null || true
  ahead=$(git -C "$REPO" rev-list --count origin/main.."origin/$BRANCH" 2>/dev/null || echo 0)
  if [[ "$ahead" -gt 0 ]]; then
    echo "PUSHED $baseline  (already on origin, $ahead commit(s) ahead of origin/main)"
    gh pr list --head "$BRANCH" --json number,title,url \
      --jq '.[] | "PR #\(.number) \(.title)\n\(.url)"' 2>/dev/null || true
    exit 0
  fi
fi

waited=0
while (( waited < TIMEOUT )); do
  sleep "$INTERVAL"; waited=$((waited+INTERVAL))
  current="$(git -C "$REPO" ls-remote origin "$BRANCH" | awk '{print $1}')"
  if [[ -n "$current" && "$current" != "$baseline" ]]; then
    echo "PUSHED $current  (after ${waited}s)"
    gh pr list --head "$BRANCH" --json number,title,url \
      --jq '.[] | "PR #\(.number) \(.title)\n\(.url)"' 2>/dev/null || true
    exit 0
  fi
done
echo "TIMEOUT after ${TIMEOUT}s — $BRANCH not pushed/changed"
exit 1
