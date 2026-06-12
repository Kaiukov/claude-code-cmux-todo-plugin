#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_MJS="$REPO_ROOT/.opencode/plugins/cmux-board.mjs"

if [[ ! -f "$PLUGIN_MJS" ]]; then
  echo "FAIL: cmux-board.mjs not found at $PLUGIN_MJS"
  exit 1
fi

# Resolve bin dir via node, passing __dirname override
run_resolve() {
  local test_dir="$1"
  shift
  node --input-type=module -e "
    import { existsSync } from 'node:fs'
    import { dirname, resolve, join } from 'node:path'

    const __dirname = '${test_dir}'

    function resolveBinDir() {
      if (process.env.CMUX_BOARD_HOME) {
        const candidate = join(process.env.CMUX_BOARD_HOME, 'bin', 'board-status')
        if (existsSync(candidate)) return join(process.env.CMUX_BOARD_HOME, 'bin')
      }
      let dir = __dirname
      for (let i = 0; i < 10; i++) {
        const candidate = join(dir, 'bin', 'board-status')
        if (existsSync(candidate)) return join(dir, 'bin')
        const parent = dirname(dir)
        if (parent === dir) break
        dir = parent
      }
      return resolve(__dirname, '..', '..', 'bin')
    }

    console.log(resolveBinDir())
  " "$@"
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "=== test_opencode_bin_resolve.sh ==="

# -------------------------------------------------------------------
echo "--- Test 1: walk-up finds bin/board-status two levels up ---"
mkdir -p "$TMPDIR/repo/.opencode/plugins"
touch "$TMPDIR/repo/.opencode/plugins/cmux-board.mjs"
mkdir -p "$TMPDIR/repo/bin"
touch "$TMPDIR/repo/bin/board-status"

result=$(run_resolve "$TMPDIR/repo/.opencode/plugins")
expected="$TMPDIR/repo/bin"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  exit 1
fi

# -------------------------------------------------------------------
echo "--- Test 2: walk-up finds bin/ at repo root (4 levels up, deep nesting) ---"
mkdir -p "$TMPDIR/deep/vendor/plugins/my-plugin/node_modules/.opencode/plugins"
touch "$TMPDIR/deep/vendor/plugins/my-plugin/node_modules/.opencode/plugins/cmux-board.mjs"
mkdir -p "$TMPDIR/deep/bin"
touch "$TMPDIR/deep/bin/board-status"

result=$(run_resolve "$TMPDIR/deep/vendor/plugins/my-plugin/node_modules/.opencode/plugins")
expected="$TMPDIR/deep/bin"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  exit 1
fi

# -------------------------------------------------------------------
echo "--- Test 3: CMUX_BOARD_HOME overrides walk-up ---"
mkdir -p "$TMPDIR/with-env/.opencode/plugins"
touch "$TMPDIR/with-env/.opencode/plugins/cmux-board.mjs"
mkdir -p "$TMPDIR/with-env/bin"
touch "$TMPDIR/with-env/bin/board-status"
mkdir -p "$TMPDIR/external-repo/bin"
touch "$TMPDIR/external-repo/bin/board-status"

export CMUX_BOARD_HOME="$TMPDIR/external-repo"
result=$(run_resolve "$TMPDIR/with-env/.opencode/plugins")
unset CMUX_BOARD_HOME
expected="$TMPDIR/external-repo/bin"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  exit 1
fi

# -------------------------------------------------------------------
echo "--- Test 4: CMUX_BOARD_HOME set but bin/board-status missing → fallback to walk-up ---"
mkdir -p "$TMPDIR/bad-env/.opencode/plugins"
touch "$TMPDIR/bad-env/.opencode/plugins/cmux-board.mjs"
mkdir -p "$TMPDIR/bad-env/bin"
touch "$TMPDIR/bad-env/bin/board-status"

export CMUX_BOARD_HOME="/nonexistent/path"
result=$(run_resolve "$TMPDIR/bad-env/.opencode/plugins")
unset CMUX_BOARD_HOME
expected="$TMPDIR/bad-env/bin"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  exit 1
fi

# -------------------------------------------------------------------
echo "--- Test 5: no bin/ found during walk-up → relative fallback ---"
mkdir -p "$TMPDIR/nobin/.opencode/plugins"
touch "$TMPDIR/nobin/.opencode/plugins/cmux-board.mjs"
# No bin/ directory anywhere up the tree

result=$(run_resolve "$TMPDIR/nobin/.opencode/plugins")
expected="$TMPDIR/nobin/bin"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  exit 1
fi

# -------------------------------------------------------------------
echo "--- Test 6: repo-local resolution matches real bin/ directory ---"
result=$(run_resolve "$REPO_ROOT/.opencode/plugins")
expected="$REPO_ROOT/bin"
if [[ "$result" == "$expected" ]]; then
  echo "PASS: real repo bin/ resolved correctly ($result)"
else
  echo "FAIL: got '$result', expected '$expected'"
  exit 1
fi

echo ""
echo "All opencode bin resolution tests passed."
