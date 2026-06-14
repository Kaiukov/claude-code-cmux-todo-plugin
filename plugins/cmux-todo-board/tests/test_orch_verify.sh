#!/usr/bin/env bash
# test_orch_verify.sh — orch-verify should delegate to shared verify.sh hermetically.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCH_VERIFY="$REPO_ROOT/bin/orch-verify"

if [[ ! -x "$ORCH_VERIFY" ]]; then
  echo "FAIL: orch-verify not found at $ORCH_VERIFY"
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/skills/cmux-agent-workflows/scripts"
STUB_LOG="$TMPDIR/verify.log"

cat > "$TMPDIR/skills/cmux-agent-workflows/scripts/verify.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "${ORCH_VERIFY_LOG:?}"
printf 'stubbed verify\n'
EOF
chmod +x "$TMPDIR/skills/cmux-agent-workflows/scripts/verify.sh"

export ORCH_VERIFY_LOG="$STUB_LOG"
export ORCH_VERIFY_SCRIPT="$TMPDIR/skills/cmux-agent-workflows/scripts/verify.sh"

output="$(cd "$TMPDIR" && bash "$ORCH_VERIFY")"
expected_repo_root="$(cd "$REPO_ROOT/../.." && pwd)"
actual_args=()
while IFS= read -r line; do
  actual_args+=("$line")
done < "$STUB_LOG"
expected_args=("$expected_repo_root")

if [[ "$output" == "stubbed verify" ]]; then
  echo "PASS: delegates to shared verify.sh"
else
  echo "FAIL: unexpected output: $output"
  exit 1
fi

if [[ ${#actual_args[@]} -eq ${#expected_args[@]} && "${actual_args[0]}" == "${expected_args[0]}" ]]; then
  echo "PASS: repo-root argument passed to shared verify.sh"
else
  echo "FAIL: args mismatch"
  printf 'expected: %q\n' "${expected_args[@]}"
  printf 'actual:   %q\n' "${actual_args[@]}"
  exit 1
fi

echo "All orch-verify tests passed."
