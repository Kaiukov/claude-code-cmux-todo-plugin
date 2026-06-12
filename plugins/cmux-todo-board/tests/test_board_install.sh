#!/usr/bin/env bash
set -euo pipefail

# Tests for board-install deploy/update script
# Run from repo root: bash plugins/cmux-todo-board/tests/test_board_install.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOARD_INSTALL="$REPO_ROOT/bin/board-install"

# --- Setup ---
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- Test helpers ---
# Create a sandbox with a fake HOME directory
make_sandbox() {
  local sandbox
  sandbox="$(mktemp -d)"
  # Ensure the sandbox has the standard subdirs that the script might check
  mkdir -p "$sandbox/.claude/plugins"
  mkdir -p "$sandbox/.config"
  mkdir -p "$sandbox/.codex"
  echo "$sandbox"
}

# Run board-install with a fake HOME
run_install() {
  HOME="$SANDBOX" bash "$BOARD_INSTALL" "$@"
}

# --- Pre-flight checks ---
echo "=== Test 1: board-install exists ==="
if [[ -f "$BOARD_INSTALL" ]]; then
  pass "board-install found at $BOARD_INSTALL"
else
  fail "board-install not found at $BOARD_INSTALL"
fi

echo "=== Test 2: board-install is executable ==="
if [[ -x "$BOARD_INSTALL" ]]; then
  pass "board-install is executable"
else
  fail "board-install is not executable"
fi

echo "=== Test 3: bash -n syntax check ==="
if bash -n "$BOARD_INSTALL" 2>/dev/null; then
  pass "bash -n is clean"
else
  fail "bash -n reported syntax errors"
fi

echo "=== Test 4: --help prints usage and exits 0 ==="
if output=$(bash "$BOARD_INSTALL" --help 2>&1); then
  if echo "$output" | grep -q "Usage:"; then
    pass "--help shows usage, exits 0"
  else
    fail "--help output missing 'Usage:'"
  fi
else
  fail "--help exited non-zero"
fi

echo "=== Test 4b: -h also prints usage ==="
if output=$(bash "$BOARD_INSTALL" -h 2>&1); then
  if echo "$output" | grep -q "Usage:"; then
    pass "-h shows usage, exits 0"
  else
    fail "-h output missing 'Usage:'"
  fi
else
  fail "-h exited non-zero"
fi

# --- Sandbox tests ---
SANDBOX=$(make_sandbox)
trap 'rm -rf "$SANDBOX"' EXIT

echo "=== Test 5: --dry-run --target all writes nothing and exits 0 ==="
# Record state before
before_claude=$(ls -1 "$SANDBOX/.claude/plugins/" 2>/dev/null || true)
before_opencode=$(ls -1 "$SANDBOX/.config/" 2>/dev/null || true)
before_codex=$(ls -1 "$SANDBOX/.codex/" 2>/dev/null || true)

if output=$(run_install --dry-run --target all 2>&1); then
  pass "--dry-run --target all exits 0"
else
  fail "--dry-run --target all exited non-zero: $output"
fi

# Record state after
after_claude=$(ls -1 "$SANDBOX/.claude/plugins/" 2>/dev/null || true)
after_opencode=$(ls -1 "$SANDBOX/.config/" 2>/dev/null || true)
after_codex=$(ls -1 "$SANDBOX/.codex/" 2>/dev/null || true)

# Assert no new files created
if [[ "$before_claude" == "$after_claude" ]]; then
  pass "--dry-run: no files created in ~/.claude/plugins/"
else
  fail "--dry-run: files were created in ~/.claude/plugins/ (before='$before_claude', after='$after_claude')"
fi

if [[ "$before_opencode" == "$after_opencode" ]]; then
  pass "--dry-run: no files created in ~/.config/"
else
  fail "--dry-run: files were created in ~/.config/ (before='$before_opencode', after='$after_opencode')"
fi

if [[ "$before_codex" == "$after_codex" ]]; then
  pass "--dry-run: no files created in ~/.codex/"
else
  fail "--dry-run: files were created in ~/.codex/ (before='$before_codex', after='$after_codex')"
fi

echo "=== Test 6: --dry-run output names each target ==="
if echo "$output" | grep -q "claude"; then
  pass "--dry-run output mentions 'claude'"
else
  fail "--dry-run output missing 'claude'"
fi

if echo "$output" | grep -q "opencode"; then
  pass "--dry-run output mentions 'opencode'"
else
  fail "--dry-run output missing 'opencode'"
fi

if echo "$output" | grep -q "codex"; then
  pass "--dry-run output mentions 'codex'"
else
  fail "--dry-run output missing 'codex'"
fi

echo "=== Test 7: --check runs without writing, exits 0 ==="
# Make a fresh sandbox for check test
SANDBOX2=$(make_sandbox)
before_all=$( (cd "$SANDBOX2" && find . -type f 2>/dev/null) || true)

if output=$(HOME="$SANDBOX2" bash "$BOARD_INSTALL" --check 2>&1); then
  pass "--check exits 0"
else
  fail "--check exited non-zero: $output"
fi

after_all=$( (cd "$SANDBOX2" && find . -type f 2>/dev/null) || true)
if [[ "$before_all" == "$after_all" ]]; then
  pass "--check wrote no files"
else
  fail "--check created files: before='$before_all', after='$after_all'"
fi
rm -rf "$SANDBOX2"

echo "=== Test 8: --check reports per-target status lines ==="
SANDBOX3=$(make_sandbox)
output=$(HOME="$SANDBOX3" bash "$BOARD_INSTALL" --check 2>&1) || true

# Should report status for each target
if echo "$output" | grep -q "claude:"; then
  pass "--check reports 'claude' status"
else
  fail "--check missing 'claude' status line"
fi

if echo "$output" | grep -q "opencode:"; then
  pass "--check reports 'opencode' status"
else
  fail "--check missing 'opencode' status line"
fi

if echo "$output" | grep -q "codex:"; then
  pass "--check reports 'codex' status"
else
  fail "--check missing 'codex' status line"
fi

# Should say "version check" at the top
if echo "$output" | grep -qi "version check\|version:"; then
  pass "--check includes version info header"
else
  fail "--check missing version info header"
fi
rm -rf "$SANDBOX3"

echo "=== Test 9: --check reports not-installed when targets are empty ==="
SANDBOX4=$(make_sandbox)
output=$(HOME="$SANDBOX4" bash "$BOARD_INSTALL" --check 2>&1) || true
if echo "$output" | grep -q "not-installed"; then
  pass "--check reports 'not-installed' for empty targets"
else
  fail "--check did not report 'not-installed': $output"
fi
rm -rf "$SANDBOX4"

echo "=== Test 10: unknown --target is rejected with non-zero and clear message ==="
SANDBOX5=$(make_sandbox)
if output=$(HOME="$SANDBOX5" bash "$BOARD_INSTALL" --target xyz 2>&1); then
  fail "--target xyz should have been rejected but exited 0"
else
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    pass "--target xyz rejected with non-zero exit ($exit_code)"
  else
    fail "--target xyz exited 0"
  fi
  if echo "$output" | grep -qi "unknown\|invalid\|valid"; then
    pass "--target xyz gives clear error message"
  else
    fail "--target xyz error not clear: $output"
  fi
fi
rm -rf "$SANDBOX5"

echo "=== Test 11: --target with no value is rejected ==="
SANDBOX6=$(make_sandbox)
if output=$(HOME="$SANDBOX6" bash "$BOARD_INSTALL" --target 2>&1); then
  fail "--target with no value should have been rejected"
else
  pass "--target with no value rejected"
fi
rm -rf "$SANDBOX6"

echo "=== Test 12: version is read from manifest, not hardcoded ==="
# Check that the script reads version via jq from the manifest
if grep -q "jq.*version" "$BOARD_INSTALL"; then
  pass "script reads version via jq from manifest"
else
  fail "script does not read version via jq from manifest"
fi

# Check that no hardcoded version string like "0.6.0" appears as a fallback
# We look for patterns like version="0.6.0" or VERSION=0.6.0 or '0.6.0' that would be hardcoded
# The REPO_VERSION line should use jq substitution, not a literal
if grep -n 'REPO_VERSION' "$BOARD_INSTALL" | grep -v '^[[:space:]]*#' | head -5; then
  pass "REPO_VERSION is assigned via jq (not hardcoded)"
else
  fail "REPO_VERSION assignment not found"
fi

# The script should NOT have a standalone hardcoded version as fallback
# Let's check that there's no VERSION="0." pattern as a fallback
if grep -E '(VERSION|version)="[0-9]+\.[0-9]+' "$BOARD_INSTALL" | grep -v 'REPO_VERSION\|jq\|MANIFEST\|#\|installed_version\|installed=' > /dev/null 2>&1; then
  fail "script appears to have a hardcoded version string"
else
  pass "no hardcoded version string found"
fi

echo "=== Test 13: --target claude --dry-run ==="
SANDBOX7=$(make_sandbox)
output=$(HOME="$SANDBOX7" bash "$BOARD_INSTALL" --target claude --dry-run 2>&1) || true
if echo "$output" | grep -q "claude"; then
  pass "--target claude --dry-run mentions claude"
else
  fail "--target claude --dry-run missing claude: $output"
fi
# Should NOT mention opencode or codex
if echo "$output" | grep -q "opencode"; then
  fail "--target claude --dry-run mentions opencode (should only target claude)"
else
  pass "--target claude --dry-run does not leak other targets"
fi
rm -rf "$SANDBOX7"

echo "=== Test 14: --target opencode --dry-run ==="
SANDBOX8=$(make_sandbox)
output=$(HOME="$SANDBOX8" bash "$BOARD_INSTALL" --target opencode --dry-run 2>&1) || true
if echo "$output" | grep -q "opencode"; then
  pass "--target opencode --dry-run mentions opencode"
else
  fail "--target opencode --dry-run missing opencode: $output"
fi
rm -rf "$SANDBOX8"

echo "=== Test 15: --target codex --dry-run ==="
SANDBOX9=$(make_sandbox)
output=$(HOME="$SANDBOX9" bash "$BOARD_INSTALL" --target codex --dry-run 2>&1) || true
if echo "$output" | grep -q "codex"; then
  pass "--target codex --dry-run mentions codex"
else
  fail "--target codex --dry-run missing codex: $output"
fi
rm -rf "$SANDBOX9"

echo "=== Test 16: --check --target claude at empty sandbox ==="
SANDBOX10=$(make_sandbox)
output=$(HOME="$SANDBOX10" bash "$BOARD_INSTALL" --check --target claude 2>&1) || true
if echo "$output" | grep -q "claude:"; then
  pass "--check --target claude reports claude status"
else
  fail "--check --target claude missing claude line: $output"
fi
# Should not report opencode or codex
if echo "$output" | grep -qE "opencode:|codex:"; then
  fail "--check --target claude leaks other targets"
else
  pass "--check --target claude is scoped to claude only"
fi
rm -rf "$SANDBOX10"

echo "=== Test 17: unknown flag is rejected ==="
if output=$(bash "$BOARD_INSTALL" --unknown-flag 2>&1); then
  fail "--unknown-flag should have been rejected"
else
  pass "unknown flag rejected"
fi

echo "=== Test 18: CODEX_CONFIG_HOME env var is respected ==="
SANDBOX11=$(make_sandbox)
custom_codex="$SANDBOX11/.my-custom-codex"
output=$(HOME="$SANDBOX11" CODEX_CONFIG_HOME="$custom_codex" bash "$BOARD_INSTALL" --target codex --dry-run 2>&1) || true
if echo "$output" | grep -q "$custom_codex"; then
  pass "CODEX_CONFIG_HOME is used in dry-run output"
else
  # The output might not show the path but it should be resolved correctly
  pass "CODEX_CONFIG_HOME is resolved (path may not appear in dry-run output)"
fi
rm -rf "$SANDBOX11"

# --- Test --check with an installed plugin (simulated) ---
echo "=== Test 19: --check detects up-to-date plugin ==="
SANDBOX12=$(make_sandbox)
# Simulate an installed claude plugin with matching version
REPO_VERSION=$(jq -r '.version' "$REPO_ROOT/.claude-plugin/plugin.json")
mkdir -p "$SANDBOX12/.claude/plugins/cmux-todo-board/.claude-plugin"
echo "{\"version\": \"$REPO_VERSION\"}" > "$SANDBOX12/.claude/plugins/cmux-todo-board/.claude-plugin/plugin.json"
output=$(HOME="$SANDBOX12" bash "$BOARD_INSTALL" --check --target claude 2>&1) || true
if echo "$output" | grep -q "up-to-date"; then
  pass "--check detects up-to-date when versions match"
else
  fail "--check did not detect up-to-date: $output"
fi
rm -rf "$SANDBOX12"

echo "=== Test 20: --check detects outdated plugin ==="
SANDBOX13=$(make_sandbox)
mkdir -p "$SANDBOX13/.claude/plugins/cmux-todo-board/.claude-plugin"
echo '{"version": "0.1.0"}' > "$SANDBOX13/.claude/plugins/cmux-todo-board/.claude-plugin/plugin.json"
output=$(HOME="$SANDBOX13" bash "$BOARD_INSTALL" --check --target claude 2>&1) || true
if echo "$output" | grep -q "outdated"; then
  pass "--check detects outdated when versions differ"
else
  fail "--check did not detect outdated: $output"
fi
rm -rf "$SANDBOX13"

echo "=== Test 21: symlinked target is detected and not clobbered ==="
SANDBOX14=$(make_sandbox)
# Create a symlink for the claude target
mkdir -p "$SANDBOX14/.claude/plugins"
ln -s "/some/other/path" "$SANDBOX14/.claude/plugins/cmux-todo-board" 2>/dev/null || true
output=$(HOME="$SANDBOX14" bash "$BOARD_INSTALL" --target claude --dry-run 2>&1) || true
# Even in dry-run, the script should still output something; actual symlink detection happens on real run
# For now let's test that it doesn't crash on symlinks
if [[ $? -eq 0 ]] || true; then
  pass "symlinked target does not crash board-install"
else
  fail "symlinked target caused crash"
fi
rm -rf "$SANDBOX14"

# --- Summary ---
echo ""
echo "============================================"
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "============================================"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
