#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOARD_MODEL="board-model"  # relative to bin/

if [[ ! -f "$REPO_ROOT/bin/board-model" ]]; then
  echo "FAIL: board-model not found at $REPO_ROOT/bin/board-model"
  exit 1
fi

# We reference board-model via relative path after cd into tempdir,
# or via the bin dir directly. Tests that need the real script will
# invoke it from the repo root via the bin/ path (no /bin/ in string).
# For PATH setup, we add the bin dir.
export PATH="$REPO_ROOT/bin:$PATH"

failures=0
PASS() { echo "PASS"; }
FAIL() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

# ============================================================
# Setup: temp HOME/cwd with stubbed pi on PATH
# ============================================================

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HOME="$TMP/home"
mkdir -p "$HOME/bin"
# Stub pi --list-models to emit canned output
cat > "$HOME/bin/pi" <<'PIEOF'
#!/usr/bin/env bash
if [[ "$1" == "--list-models" ]]; then
  cat <<'EOF'
PROVIDER      MODEL                     CONTEXT    MAX_OUT    THINKING    IMAGES
opencode      deepseek-v4-flash-free    128000     16384      yes         no
opencode-go   deepseek-v4-pro           200000     32768      yes         no
opencode      kimi-k2.6                 128000     8192       yes         no
anthropic     claude-sonnet-4-6         200000     8192       yes         yes
EOF
  exit 0
fi
echo "stub pi: unknown option $*" >&2
exit 1
PIEOF
chmod +x "$HOME/bin/pi"

export HOME
export PATH="$HOME/bin:$REPO_ROOT/bin:$PATH"

# ============================================================
# Test helper: run board-model in temp cwd
# ============================================================

# Run board-model in temp cwd. Accepts that it may fail (returns its exit code).
# Callers that expect failure must handle the exit code explicitly.
run_model() {
  ( cd "$TMP" && board-model "$@" )
}

# Like run_model but exits the test script on failure (set -e safe wrapper).
# Captures stdout+stderr; if the command fails, prints FAIL and continues.
# Always returns 0 so set -e doesn't kill the test.
run_model_ok() {
  local _out _rc=0
  _out="$( ( cd "$TMP" && board-model "$@" ) 2>&1 )" || _rc=$?
  if [[ $_rc -ne 0 ]]; then
    FAIL "board-model $* failed (rc=$_rc): $_out"
    return 0
  fi
  printf '%s\n' "$_out"
}

# Like run_model_ok but returns the actual exit code for conditional tests.
run_model_ok_strict() {
  local _out _rc=0
  _out="$( ( cd "$TMP" && board-model "$@" ) 2>&1 )" || _rc=$?
  if [[ $_rc -ne 0 ]]; then
    FAIL "board-model $* failed (rc=$_rc): $_out"
    return $_rc
  fi
  printf '%s\n' "$_out"
}

# Like run_model but expects failure. Returns 0 if it fails, 1 if it succeeds.
run_model_fail() {
  local _out
  _out="$( ( cd "$TMP" && board-model "$@" ) 2>&1 )" && {
    FAIL "board-model $* should have failed but succeeded. Output: $_out"
    return 1
  }
  return 0
}

# ============================================================
# Tests
# ============================================================

echo "=== T1: catalog --refresh writes .tasks/model-catalog.json ==="
cd "$TMP"
rm -rf .tasks
run_model_ok catalog --refresh >/dev/null || true
if [[ -f "$TMP/.tasks/model-catalog.json" ]]; then
  count="$(jq 'length' "$TMP/.tasks/model-catalog.json")"
  if [[ "$count" -ge 4 ]]; then
    PASS
  else
    FAIL "catalog has $count entries, expected >=4"
  fi
else
  FAIL "model-catalog.json not created"
fi

echo "=== T2: catalog --refresh: free=true ONLY for -free models ==="
deepseek_free="$(jq -r '.[] | select(.model == "deepseek-v4-flash-free") | .free' "$TMP/.tasks/model-catalog.json")"
kimi_free="$(jq -r '.[] | select(.model == "kimi-k2.6") | .free' "$TMP/.tasks/model-catalog.json")"
pro_free="$(jq -r '.[] | select(.model == "deepseek-v4-pro") | .free' "$TMP/.tasks/model-catalog.json")"
if [[ "$deepseek_free" == "true" && "$kimi_free" == "false" && "$pro_free" == "false" ]]; then
  PASS
else
  FAIL "free flags: deepseek-v4-flash-free=$deepseek_free kimi=$kimi_free pro=$pro_free (expected true,false,false)"
fi

echo "=== T3: catalog --json prints the cached catalog ==="
output="$(run_model_ok catalog --json 2>&1)" || true
if echo "$output" | jq -e '.[0].id' >/dev/null 2>&1; then
  PASS
else
  FAIL "catalog --json output not valid JSON array: $output"
fi

echo "=== T4: catalog (plain) prints readable output ==="
output="$(run_model_ok catalog 2>&1)" || true
if echo "$output" | grep -q "opencode" && echo "$output" | grep -q "deepseek-v4-flash-free"; then
  PASS
else
  FAIL "catalog plain output missing expected content"
fi

echo "=== T5: catalog reuses cache (no pi call on second run) ==="
# Remove pi stub to verify it's not called
mv "$HOME/bin/pi" "$HOME/bin/pi.real"
output="$(run_model_ok catalog 2>&1)" || true
mv "$HOME/bin/pi.real" "$HOME/bin/pi"
if echo "$output" | grep -q "opencode"; then
  PASS
else
  FAIL "catalog without pi stub failed to read cache: $output"
fi

echo "=== T6: catalog --refresh with missing pi exits non-zero ==="
mv "$HOME/bin/pi" "$HOME/bin/pi.real"
# Must also scrub system pi from PATH but keep /usr/bin:/bin for bash.
if ( cd "$TMP" && rm -f .tasks/model-catalog.json && PATH="$HOME/bin:$REPO_ROOT/bin:/usr/bin:/bin" board-model catalog --refresh >/dev/null 2>&1 ); then
  FAIL "catalog --refresh without pi should have failed"
else
  PASS
fi
mv "$HOME/bin/pi.real" "$HOME/bin/pi"

echo "=== T7: select --role docs --id opencode/deepseek-v4-flash-free persists ==="
cd "$TMP"
rm -f .tasks/config.json
run_model_ok catalog --refresh >/dev/null
run_model_ok select --role docs --id opencode/deepseek-v4-flash-free >/dev/null
profile_model="$(jq -r '.profiles.docs.model // empty' .tasks/config.json)"
profile_prov="$(jq -r '.profiles.docs.provider // empty' .tasks/config.json)"
if [[ "$profile_model" == "deepseek-v4-flash-free" && "$profile_prov" == "opencode" ]]; then
  PASS
else
  FAIL "expected profiles.docs = {model: deepseek-v4-flash-free, provider: opencode}, got model=$profile_model provider=$profile_prov"
fi

echo "=== T8: select --role docs --id opencode-go/deepseek-v4-pro REFUSED (paid for free-default role) ==="
cd "$TMP"
run_model_ok catalog --refresh >/dev/null
if run_model_fail select --role docs --id opencode-go/deepseek-v4-pro; then
  PASS
fi

echo "=== T9: select --role docs --id opencode-go/deepseek-v4-pro --allow-paid ACCEPTED ==="
cd "$TMP"
run_model_ok catalog --refresh >/dev/null
output="$(run_model_ok select --role docs --id opencode-go/deepseek-v4-pro --allow-paid 2>&1)" || true
profile_model="$(jq -r '.profiles.docs.model // empty' .tasks/config.json)"
if [[ "$profile_model" == "deepseek-v4-pro" ]]; then
  PASS
else
  FAIL "expected deepseek-v4-pro, got $profile_model. Output: $output"
fi

echo "=== T10: select --role frontend --id anthropic/claude-sonnet-4-6 REFUSED without --allow-claude ==="
cd "$TMP"
run_model_ok catalog --refresh >/dev/null
rm -f .tasks/config.json
if run_model_fail select --role frontend --id anthropic/claude-sonnet-4-6; then
  PASS
fi

echo "=== T11: select --role frontend --id anthropic/claude-sonnet-4-6 --allow-claude ACCEPTED ==="
cd "$TMP"
run_model_ok catalog --refresh >/dev/null
rm -f .tasks/config.json
output="$(run_model_ok select --role frontend --id anthropic/claude-sonnet-4-6 --allow-claude 2>&1)" || true
profile_model="$(jq -r '.profiles.frontend.model // empty' .tasks/config.json)"
if [[ "$profile_model" == "claude-sonnet-4-6" ]]; then
  PASS
else
  FAIL "expected claude-sonnet-4-6, got $profile_model. Output: $output"
fi

echo "=== T12: select --role backend --id opencode/does-not-exist REFUSED ==="
cd "$TMP"
run_model_ok catalog --refresh >/dev/null
if run_model_fail select --role backend --id opencode/does-not-exist; then
  PASS
fi

echo "=== T13: list shows (free) annotations from catalog ==="
cd "$TMP"
run_model_ok catalog --refresh >/dev/null
# Assign a free model to a profile so list has something to annotate
echo '{"profiles":{"docs":{"provider":"opencode","model":"deepseek-v4-flash-free"}}}' > .tasks/config.json
output="$(run_model_ok list 2>&1)" || true
if echo "$output" | grep -q "(free)"; then
  PASS
else
  FAIL "list output missing (free) annotation. Output: $output"
fi

echo "=== T14: list shows (paid) annotations for paid models ==="
cd "$TMP"
run_model_ok catalog --refresh >/dev/null
echo '{"profiles":{"backend":{"provider":"opencode-go","model":"deepseek-v4-pro"}}}' > .tasks/config.json
output="$(run_model_ok list 2>&1)" || true
if echo "$output" | grep -q "(paid)"; then
  PASS
else
  FAIL "list output missing (paid) annotation. Output: $output"
fi

echo "=== T15: list shows WARNING for paid assignments ==="
cd "$TMP"
run_model_ok catalog --refresh >/dev/null
echo '{"profiles":{"backend":{"provider":"opencode-go","model":"deepseek-v4-pro"}}}' > .tasks/config.json
output="$(run_model_ok list 2>&1)" || true
if echo "$output" | grep -qi "WARNING"; then
  PASS
else
  FAIL "list output missing WARNING for paid assignment. Output: $output"
fi

echo "=== T16: list without catalog still works (graceful degrade) ==="
cd "$TMP"
rm -f .tasks/model-catalog.json
echo '{"profiles":{"docs":{"provider":"opencode","model":"some-model"}}}' > .tasks/config.json
if run_model_ok_strict list >/dev/null 2>&1; then
  PASS
else
  FAIL "list without catalog should still work"
fi

echo "=== T17: select with invalid --id format (no slash) REFUSED ==="
cd "$TMP"
run_model_ok catalog --refresh >/dev/null
if run_model_fail select --role docs --id no-slash-here; then
  PASS
fi

echo "=== T18: select with unknown role REFUSED ==="
cd "$TMP"
run_model_ok catalog --refresh >/dev/null
if run_model_fail select --role bogus --id opencode/deepseek-v4-flash-free; then
  PASS
fi

echo "=== T22: select with no --id REFUSED ==="
cd "$TMP"
run_model_ok catalog --refresh >/dev/null
if run_model_fail select --role docs; then
  PASS
fi

echo "=== T23: select for non-frontend role with anthropic works without --allow-claude ==="
cd "$TMP"
rm -f .tasks/config.json
run_model_ok catalog --refresh >/dev/null
if run_model_ok_strict select --role backend --id anthropic/claude-sonnet-4-6 >/dev/null 2>&1; then
  PASS
else
  FAIL "anthropic + non-frontend role should be allowed"
fi

echo "=== T24: catalog with empty pi output fails gracefully ==="
# Create a pi stub that returns empty
mv "$HOME/bin/pi" "$HOME/bin/pi.real"
cat > "$HOME/bin/pi" <<'PIEOF'
#!/usr/bin/env bash
echo ""
exit 0
PIEOF
chmod +x "$HOME/bin/pi"
cd "$TMP"
rm -f .tasks/model-catalog.json
if run_model_fail catalog --refresh; then
  PASS
fi
mv "$HOME/bin/pi.real" "$HOME/bin/pi"

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All model-hub tests passed."
else
  echo "${failures} test(s) failed."
  exit 1
fi
