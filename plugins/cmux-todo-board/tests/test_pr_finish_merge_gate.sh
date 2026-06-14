#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
PR_FINISH="$REPO_ROOT/plugins/cmux-todo-board/skills/cmux-agent-workflows/scripts/pr-finish.sh"
ORCH_FINISH="$REPO_ROOT/plugins/cmux-todo-board/bin/orch-finish"
SELF="$SCRIPT_DIR/test_pr_finish_merge_gate.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

bash -n "$PR_FINISH" "$ORCH_FINISH" "$SELF"

merge_count="$(grep -c 'gh pr merge' "$PR_FINISH")"
[[ "$merge_count" == "1" ]] || fail "expected exactly one 'gh pr merge' occurrence, got $merge_count"

local_branch_line="$(grep -n 'if \[\[ "\$MERGE" -eq 0 \]\]' "$PR_FINISH" | head -n1 | cut -d: -f1)"
merge_line="$(grep -n 'gh pr merge' "$PR_FINISH" | cut -d: -f1)"
[[ -n "$local_branch_line" ]] || fail "missing local finish branch"
[[ -n "$merge_line" ]] || fail "missing gh pr merge line"
[[ "$merge_line" -gt "$local_branch_line" ]] || fail "gh pr merge is not behind the merge gate"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

real_git="$(command -v git)"
mkdir -p "$tmpdir/bin" "$tmpdir/repo"

cat > "$tmpdir/bin/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$real_git" "\$@"
EOF
chmod +x "$tmpdir/bin/git"

marker="$tmpdir/gh-called"
cat > "$tmpdir/bin/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
touch "$marker"
echo "gh stub called: \$*" >> "$tmpdir/gh.log"
exit 0
EOF
chmod +x "$tmpdir/bin/gh"

(
  cd "$tmpdir/repo"
  "$real_git" init -q
  "$real_git" config user.email test@example.com
  "$real_git" config user.name Tester
  echo "seed" > README.md
  "$real_git" add README.md
  "$real_git" commit -qm "init"

  PATH="$tmpdir/bin:$PATH" "$PR_FINISH" 123 >"$tmpdir/stdout" 2>"$tmpdir/stderr"
)

[[ ! -e "$marker" ]] || fail "local finish unexpectedly invoked gh"

echo "PASS: local finish exited without merging"
