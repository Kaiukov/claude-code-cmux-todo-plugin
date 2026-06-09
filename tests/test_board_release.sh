#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOARD_RELEASE="$REPO_ROOT/bin/board-release"

if [[ ! -f "$BOARD_RELEASE" ]]; then
  echo "FAIL: board-release not found at $BOARD_RELEASE"
  exit 1
fi

# Source the pure functions from board-release
# shellcheck source=../bin/board-release
source "$BOARD_RELEASE"

failures=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ─── bump_semver tests ──────────────────────────────────────────────────────

echo "=== Test 1: patch bump ==="
result=$(bump_semver "1.2.3" "patch")
if [[ "$result" == "1.2.4" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 2: minor bump ==="
result=$(bump_semver "1.2.3" "minor")
if [[ "$result" == "1.3.0" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 3: major bump ==="
result=$(bump_semver "1.2.3" "major")
if [[ "$result" == "2.0.0" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 4: preserves leading v on patch ==="
result=$(bump_semver "v1.2.3" "patch")
if [[ "$result" == "v1.2.4" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 5: v prefix on major bump ==="
result=$(bump_semver "v0.9.1" "major")
if [[ "$result" == "v1.0.0" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 6: v prefix on minor bump ==="
result=$(bump_semver "v2.0.0" "minor")
if [[ "$result" == "v2.1.0" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 7: reject non-semver (abc) ==="
if bump_semver "abc" "patch" 2>/dev/null; then
  echo "FAIL: should have rejected 'abc'"
  failures=$((failures+1))
else echo "PASS"; fi

echo "=== Test 8: reject short (1.2) ==="
if bump_semver "1.2" "minor" 2>/dev/null; then
  echo "FAIL: should have rejected '1.2'"
  failures=$((failures+1))
else echo "PASS"; fi

echo "=== Test 9: reject extra (1.2.3.4) ==="
if bump_semver "1.2.3.4" "patch" 2>/dev/null; then
  echo "FAIL: should have rejected '1.2.3.4'"
  failures=$((failures+1))
else echo "PASS"; fi

echo "=== Test 10: reject v1.2 (v prefix short) ==="
if bump_semver "v1.2" "minor" 2>/dev/null; then
  echo "FAIL: should have rejected 'v1.2'"
  failures=$((failures+1))
else echo "PASS"; fi

echo "=== Test 11: reject invalid bump type ==="
if bump_semver "1.0.0" "super" 2>/dev/null; then
  echo "FAIL: should have rejected 'super'"
  failures=$((failures+1))
else echo "PASS"; fi

echo "=== Test 12: 0.0.0 major bump ==="
result=$(bump_semver "0.0.0" "major")
if [[ "$result" == "1.0.0" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 13: 0.0.0 patch bump ==="
result=$(bump_semver "0.0.0" "patch")
if [[ "$result" == "0.0.1" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 14: no prefix, minor bump 0.1.0 ==="
result=$(bump_semver "0.1.0" "minor")
if [[ "$result" == "0.2.0" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

# ─── detect_stack tests ─────────────────────────────────────────────────────

echo "=== Test 15: detect node via package.json ==="
mkdir -p "$TMPDIR/node-proj"
echo '{"version":"1.0.0"}' > "$TMPDIR/node-proj/package.json"
result=$(detect_stack "$TMPDIR/node-proj")
if [[ "$result" == "node" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 16: detect python via pyproject.toml ==="
mkdir -p "$TMPDIR/python-proj"
cat > "$TMPDIR/python-proj/pyproject.toml" <<'EOF'
[project]
name = "foo"
version = "0.1.0"
EOF
result=$(detect_stack "$TMPDIR/python-proj")
if [[ "$result" == "python" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 17: detect python via __version__ ==="
mkdir -p "$TMPDIR/python-ver"
echo '__version__ = "0.2.0"' > "$TMPDIR/python-ver/app.py"
result=$(detect_stack "$TMPDIR/python-ver")
if [[ "$result" == "python" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 18: detect go via go.mod ==="
mkdir -p "$TMPDIR/go-proj"
echo 'module example.com/foo' > "$TMPDIR/go-proj/go.mod"
echo 'go 1.21' >> "$TMPDIR/go-proj/go.mod"
result=$(detect_stack "$TMPDIR/go-proj")
if [[ "$result" == "go" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 19: unknown (empty dir) ==="
mkdir -p "$TMPDIR/empty"
result=$(detect_stack "$TMPDIR/empty")
if [[ "$result" == "unknown" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 20: node takes priority over go (package.json + go.mod) ==="
mkdir -p "$TMPDIR/mixed-ng"
echo '{"version":"1.0.0"}' > "$TMPDIR/mixed-ng/package.json"
echo 'module example.com/foo' > "$TMPDIR/mixed-ng/go.mod"
result=$(detect_stack "$TMPDIR/mixed-ng")
if [[ "$result" == "node" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 21: python pyproject takes priority over __version__ ==="
mkdir -p "$TMPDIR/mixed-py"
cat > "$TMPDIR/mixed-py/pyproject.toml" <<'EOF'
[project]
version = "0.3.0"
EOF
echo '__version__ = "0.4.0"' > "$TMPDIR/mixed-py/app.py"
result=$(detect_stack "$TMPDIR/mixed-py")
if [[ "$result" == "python" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

# ─── read_version_from_source tests ─────────────────────────────────────────

echo "=== Test 22: read node version from package.json ==="
result=$(read_version_from_source "node" "$TMPDIR/node-proj")
if [[ "$result" == "1.0.0" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 23: read python version from pyproject.toml ==="
result=$(read_version_from_source "python" "$TMPDIR/python-proj")
if [[ "$result" == "0.1.0" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 24: read python version from __version__ ==="
result=$(read_version_from_source "python" "$TMPDIR/python-ver")
if [[ "$result" == "0.2.0" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 25: go falls back to git tag ==="
mkdir -p "$TMPDIR/git-tag-fallback"
git -C "$TMPDIR/git-tag-fallback" init --quiet
git -C "$TMPDIR/git-tag-fallback" config user.email "test@test.test"
git -C "$TMPDIR/git-tag-fallback" config user.name "Test"
git -C "$TMPDIR/git-tag-fallback" commit --allow-empty -m "init" --quiet
git -C "$TMPDIR/git-tag-fallback" tag -a "v1.0.0" -m "v1.0.0"
result=$(read_version_from_source "go" "$TMPDIR/git-tag-fallback")
if [[ "$result" == "v1.0.0" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 26: unknown falls back to git tag ==="
result=$(read_version_from_source "unknown" "$TMPDIR/git-tag-fallback")
if [[ "$result" == "v1.0.0" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 27: node falls back to git tag when package.json missing ==="
rm "$TMPDIR/node-proj/package.json"
git -C "$TMPDIR/node-proj" init --quiet 2>/dev/null || true
git -C "$TMPDIR/node-proj" config user.email "test@test.test"
git -C "$TMPDIR/node-proj" config user.name "Test"
git -C "$TMPDIR/node-proj" commit --allow-empty -m "init" --quiet 2>/dev/null || true
git -C "$TMPDIR/node-proj" tag -a "v3.2.1" -m "v3.2.1" 2>/dev/null || true
result=$(read_version_from_source "node" "$TMPDIR/node-proj")
if [[ "$result" == "v3.2.1" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 28: git tag picks highest semver ==="
git -C "$TMPDIR/git-tag-fallback" commit --allow-empty -m "bump" --quiet
git -C "$TMPDIR/git-tag-fallback" tag -a "v2.0.0" -m "v2.0.0"
result=$(read_version_from_source "go" "$TMPDIR/git-tag-fallback")
if [[ "$result" == "v2.0.0" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

# ─── compose_changelog_entry tests ──────────────────────────────────────────

echo "=== Test 29: changelog with all sections ==="
result=$(compose_changelog_entry "v1.0.0" "2026-06-09" "Feature A,  Feature B" "Bug fix X" "Updated deps")
expected=$'## [v1.0.0] - 2026-06-09\n\n### Added\n- Feature A\n- Feature B\n\n### Fixed\n- Bug fix X\n\n### Changed\n- Updated deps'
if [[ "$result" == "$expected" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 30: changelog with only added ==="
result=$(compose_changelog_entry "v0.1.0" "2026-01-01" "Initial release" "" "")
expected=$'## [v0.1.0] - 2026-01-01\n\n### Added\n- Initial release'
if [[ "$result" == "$expected" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 31: changelog with no sections (empty CSVs) ==="
result=$(compose_changelog_entry "v1.0.0" "2026-06-09" "" "" "")
expected=$'## [v1.0.0] - 2026-06-09'
if [[ "$result" == "$expected" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 32: changelog with only fixed ==="
result=$(compose_changelog_entry "v1.0.1" "2026-02-01" "" "Critical crash" "")
expected=$'## [v1.0.1] - 2026-02-01\n\n### Fixed\n- Critical crash'
if [[ "$result" == "$expected" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 33: changelog with only changed ==="
result=$(compose_changelog_entry "v2.0.0" "2026-03-15" "" "" "Breaking API changes")
expected=$'## [v2.0.0] - 2026-03-15\n\n### Changed\n- Breaking API changes'
if [[ "$result" == "$expected" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 34: changelog trims whitespace from items ==="
result=$(compose_changelog_entry "v0.0.1" "2025-01-01" "  item1 , item2  ,  item3" "" "")
expected=$'## [v0.0.1] - 2025-01-01\n\n### Added\n- item1\n- item2\n- item3'
if [[ "$result" == "$expected" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 35: changelog skips empty items in CSV ==="
result=$(compose_changelog_entry "v1.0.0" "2026-01-01" "A,,B" "" "")
expected=$'## [v1.0.0] - 2026-01-01\n\n### Added\n- A\n- B'
if [[ "$result" == "$expected" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

# ─── tag_version test ───────────────────────────────────────────────────────

echo "=== Test 36: tag_version adds v prefix ==="
result=$(tag_version "1.0.0")
if [[ "$result" == "v1.0.0" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo "=== Test 37: tag_version keeps existing v prefix ==="
result=$(tag_version "v1.0.0")
if [[ "$result" == "v1.0.0" ]]; then echo "PASS"; else echo "FAIL: got '$result'"; failures=$((failures+1)); fi

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All board-release pure-function tests passed."
else
  echo "${failures} test(s) failed."
  exit 1
fi
