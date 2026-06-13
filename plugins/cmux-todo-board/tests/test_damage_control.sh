#!/usr/bin/env bash
# Test: damage-control safety gate for Pi workers (#91)
#
# CI is bash-only (no node guaranteed). Tests the DATA + wiring:
#  - .pi/damage-control-rules.yaml exists, parses, and contains required patterns.
#  - --force-with-lease is NOT caught by the git push --force deny rule.
#  - agent-spawn.sh loads damage-control.ts for pi and ONLY for pi.
#  - Positive deny matches + negative (allow) cases.
#
# macOS grep -E (ERE) is used for simple patterns. PCRE lookaheads
# (used by the Node.js runtime) are tested via python3.
#
# macOS bash 3.2 compatible.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GIT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RULES_FILE="$GIT_ROOT/.pi/damage-control-rules.json"
AGENT_SPAWN="$REPO_ROOT/skills/cmux-agent-workflows/scripts/agent-spawn.sh"
FAILURES=0

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAILURES=$((FAILURES + 1)); }

# ── Helper: extract regex patterns from the JSON rules file ────────────
extract_patterns() {
  python3 -c "
import json, sys
with open('$RULES_FILE') as f:
    rules = json.load(f)
for r in rules.get('bashToolPatterns', []):
    print(r['pattern'])
"
}

# ── Helper: test a regex pattern against a command string using python3 ──
# This handles PCRE lookaheads that macOS grep -E doesn't support.
py_regex_test() {
  local pattern="$1" command="$2"
  python3 -c "
import re, sys
try:
    m = re.search(r'${pattern}', '''${command}''')
    sys.exit(0 if m else 1)
except Exception:
    sys.exit(2)
" 2>/dev/null
}

# ── Helper: check if a string exists in the rules file (simple grep) ───
# Uses -e to protect option-like patterns.
rule_contains() {
  local search="$1"
  grep -q -e "$search" "$RULES_FILE"
}

# ══════════════════════════════════════════════════════════════════════
# 1. Rules file exists and is non-empty
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 1: rules file exists ==="
if [[ -f "$RULES_FILE" ]]; then
  pass "rules file exists"
else
  fail "rules file not found at $RULES_FILE"
fi

echo "=== Test 2: rules file is non-empty ==="
if [[ -s "$RULES_FILE" ]]; then
  pass "rules file non-empty"
else
  fail "rules file empty"
fi

# ══════════════════════════════════════════════════════════════════════
# 2. JSON parses (python3 json)
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 3: JSON parses ==="
if python3 -c "import json; json.load(open('$RULES_FILE'))" 2>/dev/null; then
  pass "JSON parses via python3"
else
  fail "JSON parse failed via python3"
fi

# ══════════════════════════════════════════════════════════════════════
# 3. Required deny patterns present in rules (substring check)
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 4: required deny patterns ==="

check_rule_substring() {
  local label="$1" search="$2"
  if rule_contains "$search"; then
    pass "deny pattern present: $label"
  else
    fail "deny pattern MISSING: $label"
  fi
}

check_rule_substring "rm -rf"              'rm.*rR.*fF'
check_rule_substring "sudo rm"             'sudo.*rm'
check_rule_substring "chmod 777"           'chmod.*777'
check_rule_substring "chown -R root"       'chown.*-.*[Rr].*root'
check_rule_substring "git reset --hard"    'git.*reset.*--hard'
check_rule_substring "git clean -fd"       'git.*clean.*[fd]'
check_rule_substring "git push --force"    'git.*push.*force(?!-with-lease)'
check_rule_substring "git stash clear"     'git.*stash.*clear'
check_rule_substring "git filter-branch"   'git.*filter-branch'
check_rule_substring "remote branch --delete" 'git.*push.*--delete'
check_rule_substring "remote branch :branch"  'git.*push.*:'
check_rule_substring "> /dev/sd*"          'dev/sd'
check_rule_substring "mkfs"                'mkfs'
check_rule_substring "dd of=/dev/"         'dd.*of=/dev/'
check_rule_substring "fork bomb"           ':\(\)'

# ══════════════════════════════════════════════════════════════════════
# 4. At least 2 ask patterns present
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 5: ask patterns (min 2) ==="
ASK_COUNT=$(python3 -c "
import json
with open('$RULES_FILE') as f:
    rules = json.load(f)
print(sum(1 for r in rules.get('bashToolPatterns', []) if r.get('ask')))
" || echo 0)
if [[ "$ASK_COUNT" -ge 2 ]]; then
  pass "ask patterns found: $ASK_COUNT (>= 2)"
else
  fail "only $ASK_COUNT ask patterns found (need >= 2)"
fi

check_rule_substring "git reset (bare)"     'git.*reset'
check_rule_substring "git checkout -- ."    'git.*checkout.*--.*\.'
check_rule_substring "npm publish"          'npm.*publish'
check_rule_substring "rm -r without -f"     'rm.*-r'

# ══════════════════════════════════════════════════════════════════════
# 5. --force-with-lease is NOT caught by the git push --force deny rule
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 6: --force-with-lease not blocked ==="

PATTERNS="$(extract_patterns)"
FORCE_PATTERN=$(echo "$PATTERNS" | grep 'git.*push.*force' | grep -v 'force-with-lease' | head -1)

if [[ -z "$FORCE_PATTERN" ]]; then
  fail "could not extract git push --force pattern"
else
  echo "  force pattern: $FORCE_PATTERN"

  # Use python3 for PCRE lookahead test
  FORCE_WITH_LEASE="git push origin main --force-with-lease"
  FORCE_PLAIN="git push origin main --force"

  if py_regex_test "$FORCE_PATTERN" "$FORCE_WITH_LEASE"; then
    fail "--force-with-lease WAS matched by deny pattern (should NOT be)"
  else
    pass "--force-with-lease correctly NOT matched by deny pattern"
  fi

  if py_regex_test "$FORCE_PATTERN" "$FORCE_PLAIN"; then
    pass "--force (plain) correctly matched by deny pattern"
  else
    fail "--force (plain) NOT matched by deny pattern (should be denied)"
  fi
fi

# ══════════════════════════════════════════════════════════════════════
# 6. agent-spawn.sh loads damage-control.ts for pi and ONLY for pi
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 7: agent-spawn.sh wiring for pi ==="

if [[ ! -f "$AGENT_SPAWN" ]]; then
  fail "agent-spawn.sh not found at $AGENT_SPAWN"
else
  if grep -q '# --- #91 damage-control safety gate ---' "$AGENT_SPAWN"; then
    pass "#91 damage-control block exists in agent-spawn.sh"
  else
    fail "#91 damage-control block MISSING in agent-spawn.sh"
  fi

  if grep -A 5 '# --- #91 damage-control safety gate ---' "$AGENT_SPAWN" | grep -q 'AGENT_KIND.*pi'; then
    pass "extension load guarded by AGENT_KIND == pi"
  else
    fail "extension load NOT guarded by AGENT_KIND == pi"
  fi

  if grep -q 'damage-control.ts' "$AGENT_SPAWN"; then
    pass "agent-spawn.sh references damage-control.ts"
  else
    fail "agent-spawn.sh does NOT reference damage-control.ts"
  fi

  if grep -q '\-\-extension' "$AGENT_SPAWN"; then
    pass "agent-spawn.sh uses --extension flag"
  else
    fail "agent-spawn.sh does NOT use --extension flag"
  fi

  if grep -q '# --- end #91 ---' "$AGENT_SPAWN"; then
    pass "#91 end marker present"
  else
    fail "#91 end marker MISSING"
  fi

  if grep -B 2 'damage-control.ts' "$AGENT_SPAWN" | grep -q 'pi'; then
    pass "damage-control.ts reference is pi-guarded"
  else
    fail "damage-control.ts reference is NOT pi-guarded"
  fi

  # HARDEN: extract the --extension path from the #91 block, resolve it
  # relative to agent-spawn.sh's own directory, and assert the file exists.
  # This catches path-depth regressions (e.g. 4x .. instead of 5x ..).
  raw_ext_path="$(sed -n '/# --- #91/,/# --- end #91/p' "$AGENT_SPAWN" \
    | grep 'damage-control.ts' \
    | sed 's/.*"\$DIR\/\([^"]*\)".*/\1/' \
    | head -1)"
  if [[ -n "$raw_ext_path" ]]; then
    spawn_dir="$(dirname "$AGENT_SPAWN")"
    resolved_ext="$spawn_dir/$raw_ext_path"
    if [[ -f "$resolved_ext" ]]; then
      pass "damage-control.ts resolved from #91 block → $resolved_ext"
    else
      fail "damage-control.ts NOT FOUND from #91 block: $resolved_ext (raw: $raw_ext_path)"
    fi
  else
    fail "could not extract --extension path from #91 block"
  fi
fi

# ══════════════════════════════════════════════════════════════════════
# 7. Positive deny matches + negative (allow) cases (via python3 regex)
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 8: positive deny matches (via python3) ==="

test_regex_match() {
  local label="$1" pattern="$2" command="$3" expect_match="$4"
  if py_regex_test "$pattern" "$command"; then
    if [[ "$expect_match" == "yes" ]]; then
      pass "matched: $label"
    else
      fail "UNEXPECTED match: $label"
    fi
  else
    if [[ "$expect_match" == "yes" ]]; then
      fail "NO match: $label"
    else
      pass "correctly not matched: $label"
    fi
  fi
}

# Use python3 for all regex tests (handles PCRE lookaheads properly)
# Deny: rm -rf variants — pattern from YAML
RM_RF_PATTERN='(?<!git\s)\brm\s+(?=.*-[^-]*[rR])(?=.*-[^-]*[fF]).*'
test_regex_match "rm -rf /"                "$RM_RF_PATTERN" "rm -rf /"                    "yes"
test_regex_match "rm -rf ~"                "$RM_RF_PATTERN" "rm -rf ~"                    "yes"
test_regex_match "rm -rf ."                "$RM_RF_PATTERN" "rm -rf ."                    "yes"
test_regex_match "rm -fr /tmp/foo"         "$RM_RF_PATTERN" "rm -fr /tmp/foo"             "yes"
test_regex_match "rm -r -f /tmp/foo"       "$RM_RF_PATTERN" "rm -r -f /tmp/foo"           "yes"
test_regex_match "sudo rm -rf /"            "$RM_RF_PATTERN" "sudo rm -rf /"                "yes"

# Deny: sudo rm
test_regex_match "sudo rm -rf /"           '\bsudo\s+rm\b'              "sudo rm -rf /"               "yes"

# Deny: chmod 777
test_regex_match "chmod 777 file"          '\bchmod\s+(-[^\s]*\s+)*777\b' "chmod 777 file"          "yes"

# Deny: chown -R root
test_regex_match "chown -R root /etc"      '\bchown\s+-[Rr].*\broot\b' "chown -R root /etc"          "yes"

# Deny: git reset --hard
test_regex_match "git reset --hard HEAD"   '\bgit\s+reset\s+--hard\b'  "git reset --hard HEAD"       "yes"

# Deny: git clean -fd
test_regex_match "git clean -fd"           '\bgit\s+clean\s+.*-[fd]'    "git clean -fd"               "yes"

# Deny: git push --force (lookahead excludes --force-with-lease)
GIT_FORCE_PATTERN='\bgit\s+push\s+.*--force(?!-with-lease)'
test_regex_match "git push --force"        "$GIT_FORCE_PATTERN" "git push origin main --force" "yes"

# Deny: git stash clear
test_regex_match "git stash clear"         '\bgit\s+stash\s+clear\b'   "git stash clear"             "yes"

# Deny: mkfs
test_regex_match "mkfs.ext4 /dev/sda"      '\bmkfs\.'                   "mkfs.ext4 /dev/sda"          "yes"

# Deny: dd of=/dev/
test_regex_match "dd if=/dev/zero of=/dev/sda" '\bdd\s+.*of=/dev/'     "dd if=/dev/zero of=/dev/sda" "yes"

# Deny: fork bomb
test_regex_match "fork bomb :(){ :|:& };:"  ':\(\)\s*\{'                ":(){ :|:& };:"               "yes"

# Deny: git push --delete
test_regex_match "git push origin --delete branch" '\bgit\s+push\s+\S+\s+--delete\b' "git push origin --delete branch" "yes"

# Deny: git push origin :branch
test_regex_match "git push origin :branch" '\bgit\s+push\s+\S+\s+:\S+' "git push origin :branch"       "yes"

echo "=== Test 9: negative (allow) cases (via python3) ==="

# Should NOT match deny patterns
test_regex_match "safe: echo hello"        "$RM_RF_PATTERN"      "echo hello"                  "no"
test_regex_match "safe: ls -la"            '\bsudo\s+rm\b'       "ls -la"                      "no"
test_regex_match "safe: git status"        '\bgit\s+reset\s+--hard\b'  "git status"          "no"
test_regex_match "safe: npm install"       '\bnpm\s+publish\b'   "npm install"                 "no"
test_regex_match "safe: rm file.txt"       "$RM_RF_PATTERN"      "rm file.txt"                 "no"
test_regex_match "safe: --force-with-lease" "$GIT_FORCE_PATTERN" "git push origin main --force-with-lease" "no"
test_regex_match "safe: git reset --soft"  '\bgit\s+reset\s+--hard\b'  "git reset --soft HEAD~1" "no"
test_regex_match "safe: mkdir not mkfs"    '\bmkfs\.'            "mkdir -p /tmp/foo"           "no"

# #129: git rm with dashed paths must NOT trigger rm -rf deny rule
test_regex_match "safe: git rm a/b-c-d.md" "$RM_RF_PATTERN"      "git rm a/b-c-d.md"           "no"
test_regex_match "safe: git rm dashed-path" "$RM_RF_PATTERN"      "git rm docs/research/legacy-removal-surface.md" "no"
test_regex_match "safe: git rm plain"       "$RM_RF_PATTERN"      "git rm src/old-file.js"       "no"

# ══════════════════════════════════════════════════════════════════════
# 8. damage-control.ts has NO external yaml import (#91 regression fix)
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 10: no external yaml import in damage-control.ts ==="
DC_TS="$GIT_ROOT/.pi/extensions/damage-control.ts"
if grep -nE "from \"yaml\"|require\(['\"]yaml" "$DC_TS"; then
  fail "damage-control.ts STILL imports external yaml module"
else
  pass "no yaml import in damage-control.ts"
fi

# ══════════════════════════════════════════════════════════════════════
# 9. pi runtime smoke: load the extension in pi (skip if pi absent)
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 11: pi runtime smoke ==="
if command -v pi &>/dev/null; then
  PI_OUTPUT="$(pi --no-extensions -e "$DC_TS" -p --no-session "say ok" 2>&1)" || PI_RC=$?
  if echo "$PI_OUTPUT" | grep -qE "Cannot find module|Failed to load extension"; then
    fail "pi runtime smoke: extension load error detected"
    echo "  pi output: $PI_OUTPUT"
  elif [[ "${PI_RC:-0}" -ne 0 ]]; then
    fail "pi runtime smoke: pi exited non-zero (rc=${PI_RC:-0})"
    echo "  pi output: $PI_OUTPUT"
  else
    pass "pi runtime smoke: extension loaded cleanly"
  fi
else
  echo "SKIP: pi binary not found — skipping runtime smoke"
fi

# ══════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════
echo ""
echo "═════════════════════════════════════════════════"
if [[ "$FAILURES" -eq 0 ]]; then
  echo "All tests PASSED"
  exit 0
else
  echo "$FAILURES test(s) FAILED"
  exit 1
fi
