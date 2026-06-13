#!/usr/bin/env bash
# Tests for Pi role profiles (#102).
# Verifies board-config --get-profile resolution, deep-merge overrides,
# agent_launch_cmd thinking/tools threading, and regressions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOARD_CONFIG="$REPO_ROOT/bin/board-config"
LIB_FILE="$REPO_ROOT/skills/cmux-agent-workflows/scripts/lib.sh"

if [[ ! -f "$BOARD_CONFIG" ]]; then
  echo "FAIL: board-config not found at $BOARD_CONFIG"
  exit 1
fi
if [[ ! -f "$LIB_FILE" ]]; then
  echo "FAIL: lib.sh not found at $LIB_FILE"
  exit 1
fi

source "$LIB_FILE"

failures=0

# ── helpers ──
new_testdir() {
  TESTDIR="$(mktemp -d)"
  pushd "$TESTDIR" >/dev/null
  mkdir -p .tasks
}

cleanup_testdir() {
  popd >/dev/null || true
  rm -rf "$TESTDIR"
}

# ══════════════════════════════════════════════════════════════════════
# Test 1: board-config --get-profile backend --json
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 1: --get-profile backend --json ==="
new_testdir
json="$("$BOARD_CONFIG" --get-profile backend --json 2>&1)"
provider="$(echo "$json" | jq -r '.provider')"
thinking="$(echo "$json" | jq -r '.thinking')"
tools="$(echo "$json" | jq -r '.tools')"
model="$(echo "$json" | jq -r '.model')"
model_status="$(echo "$json" | jq -r '.model_status // empty')"
if [[ "$provider" == "opencode-go" && "$thinking" == "high" && "$tools" == "read,bash,edit,write,grep,find,ls" && -n "$model" && -z "$model_status" ]]; then
  echo "PASS  (provider=$provider thinking=$thinking tools=$tools model=$model model_status=absent)"
else
  echo "FAIL: provider=$provider thinking=$thinking tools=$tools model=$model model_status=$model_status"
  failures=$((failures + 1))
fi
cleanup_testdir

# ══════════════════════════════════════════════════════════════════════
# Test 2: each of the 5 profiles resolves with correct provider+thinking+tools
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 2: all 5 profiles resolve correctly ==="
new_testdir
all_ok=true
check_profile() {
  local profile="$1" exp_provider="$2" exp_thinking="$3" exp_tools="$4" exp_model_status="${5:-}"
  local json provider thinking tools model_status
  json="$("$BOARD_CONFIG" --get-profile "$profile" --json 2>&1)"
  provider="$(echo "$json" | jq -r '.provider')"
  thinking="$(echo "$json" | jq -r '.thinking')"
  tools="$(echo "$json" | jq -r '.tools')"
  model_status="$(echo "$json" | jq -r '.model_status // empty')"
  local ok=true
  [[ "$provider" == "$exp_provider" && "$thinking" == "$exp_thinking" && "$tools" == "$exp_tools" ]] || ok=false
  if [[ -n "$exp_model_status" ]]; then
    [[ "$model_status" == "$exp_model_status" ]] || ok=false
  else
    [[ -z "$model_status" ]] || ok=false
  fi
  if $ok; then
    echo "  $profile: PASS"
    return 0
  else
    echo "  $profile: FAIL — got provider=$provider thinking=$thinking tools=$tools model_status=$model_status"
    return 1
  fi
}
check_profile backend opencode-go high "read,bash,edit,write,grep,find,ls" || all_ok=false
check_profile frontend anthropic medium "read,bash,edit,write,grep,find,ls" TBC || all_ok=false
check_profile frontend-top anthropic high "read,bash,edit,write,grep,find,ls" TBC || all_ok=false
check_profile review opencode-go high "read,bash,grep,find,ls" || all_ok=false
check_profile docs opencode low "read,bash,edit,write,grep,find,ls" || all_ok=false
if $all_ok; then
  echo "PASS"
else
  failures=$((failures + 1))
fi
cleanup_testdir

# ══════════════════════════════════════════════════════════════════════
# Test 3: unknown profile exits non-zero
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 3: unknown profile exits non-zero ==="
new_testdir
if "$BOARD_CONFIG" --get-profile nope --json 2>/dev/null; then
  echo "FAIL: unknown profile should fail"
  failures=$((failures + 1))
else
  echo "PASS"
fi
cleanup_testdir

# ══════════════════════════════════════════════════════════════════════
# Test 4: .tasks/config.json profiles override → deep-merge proof
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 4: override one field (thinking), others keep default ==="
new_testdir
# Set up a config that overrides only thinking for backend
echo '{"profiles":{"backend":{"thinking":"minimal"}}}' > .tasks/config.json
json="$("$BOARD_CONFIG" --get-profile backend --json 2>&1)"
provider="$(echo "$json" | jq -r '.provider')"
thinking="$(echo "$json" | jq -r '.thinking')"
tools="$(echo "$json" | jq -r '.tools')"
model="$(echo "$json" | jq -r '.model')"
# Provider/model/tools should keep defaults; thinking overridden to minimal
if [[ "$provider" == "opencode-go" && "$thinking" == "minimal" && "$tools" == "read,bash,edit,write,grep,find,ls" && "$model" == "deepseek-v4-pro" ]]; then
  echo "PASS  (provider=$provider thinking=$thinking tools=$tools model=$model)"
else
  echo "FAIL: provider=$provider thinking=$thinking tools=$tools model=$model"
  failures=$((failures + 1))
fi
cleanup_testdir

# ══════════════════════════════════════════════════════════════════════
# Test 5: agent_launch_cmd pi with thinking + tools
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 5: agent_launch_cmd pi with thinking + tools ==="
cmd="$(agent_launch_cmd pi "/tmp/wt" "opencode-go/deepseek-v4-pro" high read,bash)"
expected="cd '/tmp/wt' && pi --provider opencode-go --model deepseek-v4-pro --thinking high --tools read,bash"
if [[ "$cmd" == "$expected" ]]; then
  echo "PASS"
else
  echo "FAIL: expected '$expected', got '$cmd'"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Test 6: agent_launch_cmd pi without thinking/tools (regression from #90)
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 6: agent_launch_cmd pi without thinking/tools ==="
cmd="$(agent_launch_cmd pi "/tmp/wt" "opencode-go/deepseek-v4-pro")"
expected="#90 output"
expected_full="cd '/tmp/wt' && pi --provider opencode-go --model deepseek-v4-pro"
if [[ "$cmd" == "$expected_full" ]]; then
  echo "PASS"
else
  echo "FAIL: expected '$expected_full', got '$cmd'"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Test 7: board-config --get-profile with individual selectors
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 7: --get-profile selectors ==="
new_testdir
provider="$("$BOARD_CONFIG" --get-profile backend --provider 2>&1)"
if [[ "$provider" == "opencode-go" ]]; then
  echo "  --provider: PASS"
else
  echo "  --provider: FAIL (got $provider)"
  failures=$((failures + 1))
fi

model="$("$BOARD_CONFIG" --get-profile backend --model 2>&1)"
if [[ "$model" == "deepseek-v4-pro" ]]; then
  echo "  --model: PASS"
else
  echo "  --model: FAIL (got $model)"
  failures=$((failures + 1))
fi

thinking="$("$BOARD_CONFIG" --get-profile backend --thinking 2>&1)"
if [[ "$thinking" == "high" ]]; then
  echo "  --thinking: PASS"
else
  echo "  --thinking: FAIL (got $thinking)"
  failures=$((failures + 1))
fi

tools="$("$BOARD_CONFIG" --get-profile backend --tools 2>&1)"
if [[ "$tools" == "read,bash,edit,write,grep,find,ls" ]]; then
  echo "  --tools: PASS"
else
  echo "  --tools: FAIL (got $tools)"
  failures=$((failures + 1))
fi

# Default (no selector) prints model
default="$("$BOARD_CONFIG" --get-profile backend 2>&1)"
if [[ "$default" == "deepseek-v4-pro" ]]; then
  echo "  default (model): PASS"
else
  echo "  default (model): FAIL (got $default)"
  failures=$((failures + 1))
fi
cleanup_testdir

# ══════════════════════════════════════════════════════════════════════
# Test 10: pi launch with extra args after thinking/tools
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 8: pi launch with thinking + tools + extra args ==="
cmd="$(agent_launch_cmd pi "/tmp/wt" "p/m" high read,bash extra1 extra2)"
if [[ "$cmd" == *"--thinking high --tools read,bash extra1 extra2"* ]]; then
  echo "PASS"
else
  echo "FAIL: got '$cmd'"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Test 11: full Pi thinking enum (off|minimal|low|medium|high|xhigh)
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 9: full Pi thinking enum (off|minimal|low|medium|high|xhigh) ==="
for level in off minimal low medium high xhigh; do
  cmd="$(agent_launch_cmd pi "/tmp/wt" "p/m" "$level" "t1,t2")"
  if [[ "$cmd" == *"--thinking $level --tools t1,t2"* ]]; then
    echo "  thinking=$level: PASS"
  else
    echo "  thinking=$level: FAIL — got '$cmd'"
    failures=$((failures + 1))
  fi
done

# ══════════════════════════════════════════════════════════════════════
# Test 12: end-to-end: resolved pi command from a profile contains
#          --provider / --model / --thinking / --tools and NEVER --profile
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 10: end-to-end profile→pi command ==="
new_testdir
# Simulate what agent-spawn.sh does when --profile backend is used
profile_json="$("$BOARD_CONFIG" --get-profile backend --json 2>&1)"
provider="$(echo "$profile_json" | jq -r '.provider')"
model="$(echo "$profile_json" | jq -r '.model')"
thinking="$(echo "$profile_json" | jq -r '.thinking')"
tools="$(echo "$profile_json" | jq -r '.tools')"
pi_model="$provider/$model"
cmd="$(agent_launch_cmd pi "/tmp/wt" "$pi_model" "$thinking" "$tools")"
if [[ "$cmd" == *"--provider $provider"* && "$cmd" == *"--model $model"* && "$cmd" == *"--thinking $thinking"* && "$cmd" == *"--tools $tools"* ]]; then
  echo "  flags present: PASS"
else
  echo "  flags present: FAIL — got '$cmd'"
  failures=$((failures + 1))
fi
if [[ "$cmd" != *"--profile"* ]]; then
  echo "  no --profile: PASS"
else
  echo "  no --profile: FAIL — --profile leaked into '$cmd'"
  failures=$((failures + 1))
fi
cleanup_testdir

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All pi profiles tests passed."
else
  echo "$failures test(s) failed."
  exit 1
fi
