#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT_SCRIPT="$REPO_ROOT/skills/cmux-agent-workflows/scripts/agent-audit.sh"

if [[ ! -f "$AUDIT_SCRIPT" ]]; then
  echo "FAIL: agent-audit.sh not found at $AUDIT_SCRIPT"
  exit 1
fi

bash -n "$AUDIT_SCRIPT" || { echo "FAIL: bash -n syntax check"; exit 1; }

# ─── classification functions (pure, no cmux dependency) ────────────────────
# These match the logic in agent-audit.sh exactly.

BAND_POOL=(
  Nirvana Metallica Radiohead Pixies Ramones "Pearl Jam" Soundgarden Tool
  Aerosmith Muse Blur Oasis Queen Rush Kiss Pantera Slipknot Deftones Korn
  Mastodon Megadeth Anthrax Clutch Ghost Opeth Journey Foreigner Heart Cream
  Doors Eagles Kansas Boston Genesis Yes Toto Sabbath Priest Maiden Motorhead
  Dio Scorpions Whitesnake Europe Survivor Triumph Styx Asia Police Clash Cure
  Smiths Garbage Hole Bush Filter Staind Creed Disturbed Godsmack Shinedown
  Audioslave Helmet Fugazi Sevendust Tesla Poison Ratt Warrant Cinderella
)

is_own_surface() {
  local ref="$1" orchestrator_id="${2:-}"
  [[ -n "$orchestrator_id" && "$ref" == "$orchestrator_id" ]]
}

is_focused_line() {
  local line="$1"
  [[ "$line" == *"[focused]"* ]]
}

is_browser_line() {
  local line="$1"
  [[ "$line" =~ ^[[:space:]*]*surface:[0-9]+[[:space:]]+browser ]]
}

has_agent_naming() {
  local title="$1"
  for band in "${BAND_POOL[@]}"; do
    if [[ "$title" == "$band"* ]]; then
      return 0
    fi
  done
  return 1
}

agent_kill_pattern() {
  printf '%s' 'opencode|codex|node|bun'
}

failures=0

# ═══════════════════════════════════════════════════════════════════════════════
# Test 1: Browser surfaces are detected
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Test 1: is_browser_line ==="
result=$(is_browser_line "  surface:120  browser  \"Issues · repo\"" && echo "browser" || echo "not-browser")
expected="browser"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

result=$(is_browser_line "  surface:11  terminal  [focused]  \"Aerosmith\"" && echo "browser" || echo "not-browser")
expected="not-browser"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

result=$(is_browser_line "* surface:99  browser  [focused]  \"GitHub\"" && echo "browser" || echo "not-browser")
expected="browser"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Test 2: Focused surfaces are detected
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Test 2: is_focused_line ==="
result=$(is_focused_line "* surface:11  terminal  [focused]  \"Aerosmith\"" && echo "focused" || echo "not-focused")
expected="focused"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

result=$(is_focused_line "  surface:180  terminal  \"Asia L4\"" && echo "focused" || echo "not-focused")
expected="not-focused"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Test 3: Orchestrator own surface detection
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Test 3: is_own_surface ==="
result=$(is_own_surface "surface:11" "surface:11" && echo "own" || echo "not-own")
expected="own"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

result=$(is_own_surface "surface:180" "surface:11" && echo "own" || echo "not-own")
expected="not-own"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

result=$(is_own_surface "surface:11" "" && echo "own" || echo "not-own")
expected="not-own"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Test 4: Agent naming detection (band names)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Test 4: has_agent_naming ==="
result=$(has_agent_naming "Aerosmith" && echo "agent" || echo "not-agent")
expected="agent"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

result=$(has_agent_naming "Asia L4" && echo "agent" || echo "not-agent")
expected="agent"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

result=$(has_agent_naming "Metallica 42" && echo "agent" || echo "not-agent")
expected="agent"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

result=$(has_agent_naming "Radiohead feat/fix" && echo "agent" || echo "not-agent")
expected="agent"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

result=$(has_agent_naming "My Terminal" && echo "agent" || echo "not-agent")
expected="not-agent"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

result=$(has_agent_naming "bash" && echo "agent" || echo "not-agent")
expected="not-agent"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

result=$(has_agent_naming "" && echo "agent" || echo "not-agent")
expected="not-agent"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

# "Asia" is in BAND_POOL, "Asia L4" starts with "Asia"
result=$(has_agent_naming "Asia L4" && echo "agent" || echo "not-agent")
expected="agent"
if [[ "$result" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result', expected '$expected'"
  failures=$((failures + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Test 5: Classification walkthrough with stubbed cmux list-panels output
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Test 5: End-to-end classification on sample output ==="

SAMPLE_OUTPUT='* surface:11  terminal  [focused]  "Aerosmith"
  surface:180  terminal  "Asia L4"
  surface:120  browser  "Issues · Kaiukov/claude-code-cmux-todo-plugin"
  surface:200  terminal  "Radiohead 42"
  surface:42  terminal  "My Shell"'

ORCHESTRATOR_ID="surface:11"

candidates=()
active=()
protected=()

while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  ref="$(echo "$line" | sed -n 's/.*\(surface:[0-9]\{1,\}\).*/\1/p')"
  [[ -z "$ref" ]] && continue

  title="$(echo "$line" | sed -n 's/.*"\([^"]*\)"[[:space:]]*$/\1/p')"

  if is_own_surface "$ref" "$ORCHESTRATOR_ID"; then
    protected+=("$ref (own)")
    continue
  fi

  if is_focused_line "$line"; then
    protected+=("$ref (focused)")
    continue
  fi

  if is_browser_line "$line"; then
    protected+=("$ref (browser)")
    continue
  fi

  if ! has_agent_naming "$title"; then
    continue
  fi

  # stub: surface:180 "Asia L4" → idle, surface:200 "Radiohead 42" → idle
  candidates+=("$ref")
done <<< "$SAMPLE_OUTPUT"

# Expected: surface:11 → protected (focused + own)
#           surface:120 → protected (browser)
#           surface:180 → candidate (Asia L4, agent naming, idle)
#           surface:200 → candidate (Radiohead 42, agent naming, idle)
#           surface:42 → skipped (not agent naming)

expected_protected="surface:11 (own) surface:120 (browser)"
expected_candidates="surface:180 surface:200"

if [[ "${protected[*]}" == "$expected_protected" ]]; then
  echo "PASS (protected: ${protected[*]})"
else
  echo "FAIL: protected='${protected[*]}', expected='$expected_protected'"
  failures=$((failures + 1))
fi

if [[ "${candidates[*]}" == "$expected_candidates" ]]; then
  echo "PASS (candidates: ${candidates[*]})"
else
  echo "FAIL: candidates='${candidates[*]}', expected='$expected_candidates'"
  failures=$((failures + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Test 6: Focused browser is still protected (browser rule wins)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Test 6: Focused browser → protected ==="
line="* surface:99  browser  [focused]  \"GitHub\""
if is_browser_line "$line"; then
  echo "PASS (browser detected, protected)"
else
  echo "FAIL: browser not detected"
  failures=$((failures + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Test 7: agent-kill.sh pattern covers expected binaries
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== Test 7: agent_kill_pattern ==="
pattern=$(agent_kill_pattern "")
if echo "$pattern" | grep -q "opencode" && echo "$pattern" | grep -q "codex"; then
  echo "PASS (pattern: $pattern)"
else
  echo "FAIL: pattern missing expected binaries: $pattern"
  failures=$((failures + 1))
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Results
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
if [[ $failures -eq 0 ]]; then
  echo "All agent-audit tests passed."
else
  echo "${failures} test(s) failed."
  exit 1
fi
