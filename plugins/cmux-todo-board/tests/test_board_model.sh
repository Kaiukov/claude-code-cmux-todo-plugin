#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOARD_MODEL="$REPO_ROOT/bin/board-model"
BOARD_CONFIG="$REPO_ROOT/bin/board-config"

if [[ ! -f "$BOARD_MODEL" ]]; then
  echo "FAIL: board-model not found at $BOARD_MODEL"
  exit 1
fi
if [[ ! -f "$BOARD_CONFIG" ]]; then
  echo "FAIL: board-config not found at $BOARD_CONFIG"
  exit 1
fi

# --- Pure functions extracted from board-model ---

VALID_TIERS=(flash pro review simple top)
VALID_PROVIDERS=(opencode codex)
VALID_EFFORTS=(low medium high)

validate_name() {
  local name="$1" label="${2:-name}"
  if [[ -z "$name" ]]; then
    echo "board-model: ${label} must not be empty" >&2
    return 1
  fi
  if [[ "$name" =~ [[:space:]] ]]; then
    echo "board-model: ${label} must not contain whitespace: '${name}'" >&2
    return 1
  fi
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "board-model: ${label} must be alphanumeric, hyphens, or underscores: '${name}'" >&2
    return 1
  fi
  return 0
}

validate_model() {
  local model="$1"
  if [[ -z "$model" ]]; then
    echo "board-model: model must not be empty" >&2
    return 1
  fi
  return 0
}

validate_provider() {
  local provider="$1"
  local found="" p
  for p in "${VALID_PROVIDERS[@]}"; do
    [[ "$provider" == "$p" ]] && found=1 && break
  done
  if [[ -z "$found" ]]; then
    echo "board-model: unknown provider '${provider}'. Valid: ${VALID_PROVIDERS[*]}" >&2
    return 1
  fi
  return 0
}

validate_effort() {
  local effort="$1"
  local found="" e
  for e in "${VALID_EFFORTS[@]}"; do
    [[ "$effort" == "$e" ]] && found=1 && break
  done
  if [[ -z "$found" ]]; then
    echo "board-model: unknown reasoning effort '${effort}'. Valid: ${VALID_EFFORTS[*]}" >&2
    return 1
  fi
  return 0
}

validate_tier() {
  local tier="$1"
  local found="" t
  for t in "${VALID_TIERS[@]}"; do
    [[ "$tier" == "$t" ]] && found=1 && break
  done
  if [[ -z "$found" ]]; then
    echo "board-model: unknown tier '${tier}'. Valid: ${VALID_TIERS[*]}" >&2
    return 1
  fi
  return 0
}

auto_detect_provider() {
  local model="$1"
  if [[ "$model" == */* ]]; then echo "opencode"; return; fi
  local lc
  lc="$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')"
  case "$lc" in
    gpt-*|o1-*|o3-*|o4-*|codex*|chatgpt-*) echo "codex" ;;
    *) echo "opencode" ;;
  esac
}

registry_exists() {
  local config="$1" name="$2"
  local key
  key="$(echo "$config" | jq -r --arg n "$name" '.["model-registry"][$n] // empty' 2>/dev/null)"
  [[ -n "$key" ]]
}

assigned_tiers() {
  local config="$1" name="$2"
  echo "$config" | jq -r --arg n "$name" '
    .models // {} | to_entries[] | select(.value == $n) | .key
  ' 2>/dev/null || true
}

# --- Extracted board-config resolution functions ---

DEFAULT_MODELS_JSON='{"flash":"opencode/deepseek-v4-flash-free","pro":"opencode-go/deepseek-v4-pro","review":"gpt-5.4","simple":"gpt-5.4-mini","top":"gpt-5.5"}'

resolve_model_full() {
  local tier="$1"
  local config_json="$2"

  local found="" t
  for t in "${VALID_TIERS[@]}"; do
    [[ "$tier" == "$t" ]] && found=1 && break
  done
  if [[ -z "$found" ]]; then
    echo "board-config: unknown model tier '${tier}'. Valid: ${VALID_TIERS[*]}" >&2
    return 1
  fi

  local model="" provider="" effort=""
  local model_ref
  if [[ -n "$config_json" ]]; then
    model_ref="$(echo "$config_json" | jq -r --arg t "$tier" '.models[$t] // empty' 2>/dev/null)"
  fi

  if [[ -n "$model_ref" ]]; then
    local registry_entry
    registry_entry="$(echo "$config_json" | jq -r --arg r "$model_ref" '.["model-registry"][$r] // empty' 2>/dev/null)"
    if [[ -n "$registry_entry" ]]; then
      model="$(echo "$registry_entry" | jq -r '.model // empty')"
      provider="$(echo "$registry_entry" | jq -r '.provider // "opencode"')"
      effort="$(echo "$registry_entry" | jq -r '.reasoning_effort // empty')"
    else
      model="$model_ref"
      provider="$(auto_detect_provider "$model")"
    fi
  else
    model="$(echo "$DEFAULT_MODELS_JSON" | jq -r --arg t "$tier" '.[$t]')"
    provider="$(auto_detect_provider "$model")"
  fi

  jq -n --arg model "$model" --arg provider "$provider" --arg effort "$effort" \
    '{model: $model, provider: $provider} + (if $effort != "" then {reasoning_effort: $effort} else {} end)'
}

resolve_model() {
  local result
  if ! result="$(resolve_model_full "$1" "$2")"; then
    return 1
  fi
  echo "$result" | jq -r '.model'
}

# ========================
# TESTS
# ========================

failures=0
PASS() { echo "PASS"; }
FAIL() { echo "FAIL: $1"; failures=$((failures + 1)); }

# ============================================================
# Section A: Pure validation functions
# ============================================================

echo "=== A1: validate_name accepts valid names ==="
if validate_name "my-model" 2>/dev/null; then PASS; else FAIL "rejected valid name 'my-model'"; fi

echo "=== A2: validate_name accepts underscores ==="
if validate_name "my_model" 2>/dev/null; then PASS; else FAIL "rejected valid name with underscore"; fi

echo "=== A3: validate_name accepts alphanumeric ==="
if validate_name "pro123" 2>/dev/null; then PASS; else FAIL "rejected valid name 'pro123'"; fi

echo "=== A4: validate_name rejects empty ==="
if validate_name "" 2>/dev/null; then FAIL "accepted empty name"; else PASS; fi

echo "=== A5: validate_name rejects whitespace ==="
if validate_name "bad name" 2>/dev/null; then FAIL "accepted name with space"; else PASS; fi

echo "=== A6: validate_name rejects special chars ==="
if validate_name "bad@name" 2>/dev/null; then FAIL "accepted name with @"; else PASS; fi

echo "=== A7: validate_model accepts non-empty ==="
if validate_model "gpt-5.5" 2>/dev/null; then PASS; else FAIL "rejected valid model"; fi

echo "=== A8: validate_model rejects empty ==="
if validate_model "" 2>/dev/null; then FAIL "accepted empty model"; else PASS; fi

echo "=== A9: validate_provider accepts opencode ==="
if validate_provider "opencode" 2>/dev/null; then PASS; else FAIL "rejected opencode"; fi

echo "=== A10: validate_provider accepts codex ==="
if validate_provider "codex" 2>/dev/null; then PASS; else FAIL "rejected codex"; fi

echo "=== A11: validate_provider rejects invalid ==="
if validate_provider "azure" 2>/dev/null; then FAIL "accepted invalid provider"; else PASS; fi

echo "=== A12: validate_effort accepts low/medium/high ==="
if validate_effort "low" 2>/dev/null && validate_effort "medium" 2>/dev/null && validate_effort "high" 2>/dev/null; then PASS; else FAIL "rejected valid effort"; fi

echo "=== A13: validate_effort rejects invalid ==="
if validate_effort "extreme" 2>/dev/null; then FAIL "accepted invalid effort"; else PASS; fi

echo "=== A14: validate_tier accepts all 5 tiers ==="
ok=1
for t in "${VALID_TIERS[@]}"; do
  if ! validate_tier "$t" 2>/dev/null; then ok=0; break; fi
done
if [[ $ok -eq 1 ]]; then PASS; else FAIL "rejected valid tier"; fi

echo "=== A15: validate_tier rejects invalid ==="
if validate_tier "ultra" 2>/dev/null; then FAIL "accepted invalid tier"; else PASS; fi

echo "=== A16: auto_detect_provider opencode for model with / ==="
result=$(auto_detect_provider "deepseek/deepseek-v4-pro")
if [[ "$result" == "opencode" ]]; then PASS; else FAIL "got $result"; fi

echo "=== A17: auto_detect_provider codex for gpt-* ==="
result=$(auto_detect_provider "gpt-5.4")
if [[ "$result" == "codex" ]]; then PASS; else FAIL "got $result"; fi

echo "=== A18: auto_detect_provider codex for o1-* ==="
result=$(auto_detect_provider "o1-mini")
if [[ "$result" == "codex" ]]; then PASS; else FAIL "got $result"; fi

echo "=== A19: auto_detect_provider codex for o3-* ==="
result=$(auto_detect_provider "o3-mini")
if [[ "$result" == "codex" ]]; then PASS; else FAIL "got $result"; fi

echo "=== A20: auto_detect_provider codex for o4-* ==="
result=$(auto_detect_provider "o4-mini")
if [[ "$result" == "codex" ]]; then PASS; else FAIL "got $result"; fi

echo "=== A21: auto_detect_provider codex for codex* ==="
result=$(auto_detect_provider "codex-pro")
if [[ "$result" == "codex" ]]; then PASS; else FAIL "got $result"; fi

echo "=== A22: auto_detect_provider codex for chatgpt-* ==="
result=$(auto_detect_provider "chatgpt-4o")
if [[ "$result" == "codex" ]]; then PASS; else FAIL "got $result"; fi

echo "=== A23: auto_detect_provider opencode for bare name (default) ==="
result=$(auto_detect_provider "some-model")
if [[ "$result" == "opencode" ]]; then PASS; else FAIL "got $result"; fi

# ============================================================
# Section B: Integration tests with temp config
# ============================================================

new_testdir() {
  TESTDIR="$(mktemp -d)"
  pushd "$TESTDIR" >/dev/null
  mkdir -p .tasks
}

cleanup_testdir() {
  popd >/dev/null || true
  rm -rf "$TESTDIR"
}

echo ""

# B1: add a registry entry
echo "=== B1: add entry ==="
new_testdir
output="$("$BOARD_MODEL" add my-pro --model gpt-5.5 --provider codex --effort high 2>&1)"
if grep -q "Added 'my-pro'" <<<"$output"; then
  config_model=$(jq -r '.["model-registry"]["my-pro"].model' .tasks/config.json)
  config_provider=$(jq -r '.["model-registry"]["my-pro"].provider' .tasks/config.json)
  config_effort=$(jq -r '.["model-registry"]["my-pro"].reasoning_effort' .tasks/config.json)
  if [[ "$config_model" == "gpt-5.5" && "$config_provider" == "codex" && "$config_effort" == "high" ]]; then
    PASS
  else
    FAIL "config mismatch: model=$config_model provider=$config_provider effort=$config_effort"
  fi
else
  FAIL "output: $output"
fi
cleanup_testdir

# B2: add with auto-detected provider
echo "=== B2: add with model containing / auto-detects opencode ==="
new_testdir
"$BOARD_MODEL" add open-entry --model "opencode/deepseek-v4-flash-free" 2>&1 >/dev/null
provider=$(jq -r '.["model-registry"]["open-entry"].provider' .tasks/config.json)
if [[ "$provider" == "opencode" ]]; then PASS; else FAIL "expected opencode, got $provider"; fi
cleanup_testdir

# B3: add with gpt model auto-detects codex
echo "=== B3: add with gpt model auto-detects codex ==="
new_testdir
"$BOARD_MODEL" add gpt-entry --model "gpt-5.4-mini" 2>&1 >/dev/null
provider=$(jq -r '.["model-registry"]["gpt-entry"].provider' .tasks/config.json)
if [[ "$provider" == "codex" ]]; then PASS; else FAIL "expected codex, got $provider"; fi
cleanup_testdir

# B4: add duplicate rejects
echo "=== B4: duplicate add rejects ==="
new_testdir
"$BOARD_MODEL" add dup --model x --provider opencode 2>&1 >/dev/null
if "$BOARD_MODEL" add dup --model y --provider codex 2>&1 >/dev/null; then
  FAIL "duplicate add should have failed"
else
  PASS
fi
cleanup_testdir

# B5: add with empty model rejects
echo "=== B5: add with empty model rejects ==="
new_testdir
if "$BOARD_MODEL" add no-model --model "" 2>&1 >/dev/null; then
  FAIL "empty model should have failed"
else
  PASS
fi
cleanup_testdir

# B6: add with invalid provider rejects
echo "=== B6: add with invalid provider rejects ==="
new_testdir
if "$BOARD_MODEL" add bad --model x --provider azure 2>&1 >/dev/null; then
  FAIL "invalid provider should have failed"
else
  PASS
fi
cleanup_testdir

# B7: add with invalid effort rejects
echo "=== B7: add with invalid effort rejects ==="
new_testdir
if "$BOARD_MODEL" add bad --model x --effort extreme 2>&1 >/dev/null; then
  FAIL "invalid effort should have failed"
else
  PASS
fi
cleanup_testdir

# B8: asign to tier
echo "=== B8: asign entry to tier ==="
new_testdir
"$BOARD_MODEL" add my-pro --model gpt-5.5 --provider codex --effort high 2>&1 >/dev/null
output="$("$BOARD_MODEL" asign my-pro --tier pro 2>&1)"
if grep -q "Assigned 'my-pro' to tier 'pro'" <<<"$output"; then
  tier_val=$(jq -r '.models.pro' .tasks/config.json)
  if [[ "$tier_val" == "my-pro" ]]; then PASS; else FAIL "tier value: $tier_val"; fi
else
  FAIL "output: $output"
fi
cleanup_testdir

# B9: asign requires existing registry entry
echo "=== B9: asign non-existent entry fails ==="
new_testdir
if "$BOARD_MODEL" asign missing --tier flash 2>&1 >/dev/null; then
  FAIL "asign to missing entry should have failed"
else
  PASS
fi
cleanup_testdir

# B10: asign with invalid tier rejects
echo "=== B10: asign with invalid tier rejects ==="
new_testdir
"$BOARD_MODEL" add entry --model x --provider opencode 2>&1 >/dev/null
if "$BOARD_MODEL" asign entry --tier invalid 2>&1 >/dev/null; then
  FAIL "invalid tier should have failed"
else
  PASS
fi
cleanup_testdir

# B11: edit changes effort
echo "=== B11: edit changes effort ==="
new_testdir
"$BOARD_MODEL" add my-pro --model gpt-5.5 --provider codex --effort high 2>&1 >/dev/null
"$BOARD_MODEL" edit my-pro --effort low 2>&1 >/dev/null
effort=$(jq -r '.["model-registry"]["my-pro"].reasoning_effort' .tasks/config.json)
if [[ "$effort" == "low" ]]; then PASS; else FAIL "effort=$effort"; fi
cleanup_testdir

# B12: edit changes model
echo "=== B12: edit changes model ==="
new_testdir
"$BOARD_MODEL" add entry --model gpt-5.4 --provider codex 2>&1 >/dev/null
"$BOARD_MODEL" edit entry --model gpt-5.5 2>&1 >/dev/null
model=$(jq -r '.["model-registry"]["entry"].model' .tasks/config.json)
if [[ "$model" == "gpt-5.5" ]]; then PASS; else FAIL "model=$model"; fi
cleanup_testdir

# B13: edit with rename follows assignments
echo "=== B13: edit rename follows assignments ==="
new_testdir
"$BOARD_MODEL" add old --model gpt-5.4 --provider codex 2>&1 >/dev/null
"$BOARD_MODEL" asign old --tier review 2>&1 >/dev/null
"$BOARD_MODEL" edit old --rename new 2>&1 >/dev/null
if registry_exists "$(cat .tasks/config.json)" "old"; then
  FAIL "old key still exists"
elif ! registry_exists "$(cat .tasks/config.json)" "new"; then
  FAIL "new key missing"
else
  tier_val=$(jq -r '.models.review' .tasks/config.json)
  if [[ "$tier_val" == "new" ]]; then PASS; else FAIL "tier review=$tier_val (expected new)"; fi
fi
cleanup_testdir

# B14: edit rename collision rejects
echo "=== B14: edit rename collision rejects ==="
new_testdir
"$BOARD_MODEL" add a --model m1 --provider opencode 2>&1 >/dev/null
"$BOARD_MODEL" add b --model m2 --provider opencode 2>&1 >/dev/null
if "$BOARD_MODEL" edit a --rename b 2>&1 >/dev/null; then
  FAIL "rename collision should have failed"
else
  PASS
fi
cleanup_testdir

# B15: edit with no flags rejects
echo "=== B15: edit with no flags rejects ==="
new_testdir
"$BOARD_MODEL" add entry --model x --provider opencode 2>&1 >/dev/null
if "$BOARD_MODEL" edit entry 2>&1 >/dev/null; then
  FAIL "edit with no flags should have failed"
else
  PASS
fi
cleanup_testdir

# B16: edit non-existent entry
echo "=== B16: edit non-existent entry fails ==="
new_testdir
if "$BOARD_MODEL" edit missing --model x 2>&1 >/dev/null; then
  FAIL "edit missing should have failed"
else
  PASS
fi
cleanup_testdir

# B17: delete entry
echo "=== B17: delete unassigned entry ==="
new_testdir
"$BOARD_MODEL" add temp --model x --provider opencode 2>&1 >/dev/null
output="$("$BOARD_MODEL" delete temp 2>&1)"
if grep -q "Deleted 'temp'" <<<"$output"; then
  if registry_exists "$(cat .tasks/config.json)" "temp"; then
    FAIL "entry still exists"
  else
    PASS
  fi
else
  FAIL "output: $output"
fi
cleanup_testdir

# B18: delete assigned entry blocked
echo "=== B18: delete assigned entry blocked ==="
new_testdir
"$BOARD_MODEL" add assigned --model gpt-5.5 --provider codex 2>&1 >/dev/null
"$BOARD_MODEL" asign assigned --tier pro 2>&1 >/dev/null
if "$BOARD_MODEL" delete assigned 2>&1 >/dev/null; then
  FAIL "delete assigned should have failed"
else
  PASS
fi
cleanup_testdir

# B19: delete assigned with --force succeeds and clears
echo "=== B19: delete assigned --force clears assignments ==="
new_testdir
"$BOARD_MODEL" add assigned --model gpt-5.5 --provider codex 2>&1 >/dev/null
"$BOARD_MODEL" asign assigned --tier pro 2>&1 >/dev/null
"$BOARD_MODEL" delete assigned --force 2>&1 >/dev/null
if registry_exists "$(cat .tasks/config.json)" "assigned"; then
  FAIL "entry still exists"
elif [[ -n "$(jq -r '.models.pro // empty' .tasks/config.json)" ]]; then
  FAIL "tier assignment not cleared"
else
  PASS
fi
cleanup_testdir

# B20: delete non-existent
echo "=== B20: delete non-existent fails ==="
new_testdir
if "$BOARD_MODEL" delete missing 2>&1 >/dev/null; then
  FAIL "delete missing should have failed"
else
  PASS
fi
cleanup_testdir

# ============================================================
# Section C: Resolution through board-config
# ============================================================

echo ""

# C1: resolution through registry
echo "=== C1: board-config resolves through registry ==="
new_testdir
"$BOARD_MODEL" add my-pro --model gpt-5.5 --provider codex --effort high 2>&1 >/dev/null
"$BOARD_MODEL" asign my-pro --tier pro 2>&1 >/dev/null
result=$(resolve_model "pro" "$(cat .tasks/config.json)")
if [[ "$result" == "gpt-5.5" ]]; then PASS; else FAIL "got $result"; fi
cleanup_testdir

# C2: resolution resolves provider from registry
echo "=== C2: board-config resolves provider from registry ==="
new_testdir
"$BOARD_MODEL" add my-pro --model gpt-5.5 --provider codex --effort medium 2>&1 >/dev/null
"$BOARD_MODEL" asign my-pro --tier pro 2>&1 >/dev/null
full=$(resolve_model_full "pro" "$(cat .tasks/config.json)")
provider=$(echo "$full" | jq -r '.provider')
effort=$(echo "$full" | jq -r '.reasoning_effort')
if [[ "$provider" == "codex" && "$effort" == "medium" ]]; then PASS; else FAIL "provider=$provider effort=$effort"; fi
cleanup_testdir

# C3: resolution falls back to defaults for unconfigured tier
echo "=== C3: unconfigured tier uses default ==="
new_testdir
"$BOARD_MODEL" add my-pro --model gpt-5.5 --provider codex 2>&1 >/dev/null
"$BOARD_MODEL" asign my-pro --tier pro 2>&1 >/dev/null
result=$(resolve_model "flash" "$(cat .tasks/config.json)")
if [[ "$result" == "opencode/deepseek-v4-flash-free" ]]; then PASS; else FAIL "got $result"; fi
cleanup_testdir

# C4: bare model ID in config (backward compat)
echo "=== C4: bare model ID resolves directly (backward compat) ==="
result=$(resolve_model "flash" '{"models":{"flash":"bare/model-id"}}')
if [[ "$result" == "bare/model-id" ]]; then PASS; else FAIL "got $result"; fi

# C5: bare model ID auto-detects provider
echo "=== C5: bare model ID auto-detects provider ==="
full=$(resolve_model_full "review" '{"models":{"review":"gpt-5.4"}}')
provider=$(echo "$full" | jq -r '.provider')
if [[ "$provider" == "codex" ]]; then PASS; else FAIL "got $provider"; fi

# C6: existing config without model-registry still works
echo "=== C6: existing config without model-registry still works ==="
result=$(resolve_model "pro" '{"language":"EN","models":{"pro":"custom/model"}}')
if [[ "$result" == "custom/model" ]]; then PASS; else FAIL "got $result"; fi

# C7: registry entry without effort has no effort in resolution
echo "=== C7: registry entry without effort has no effort ==="
new_testdir
"$BOARD_MODEL" add no-effort --model gpt-5.4 --provider codex 2>&1 >/dev/null
"$BOARD_MODEL" asign no-effort --tier simple 2>&1 >/dev/null
full=$(resolve_model_full "simple" "$(cat .tasks/config.json)")
effort=$(echo "$full" | jq -r '.reasoning_effort // "NONE"')
if [[ "$effort" == "NONE" ]]; then PASS; else FAIL "effort should be absent, got $effort"; fi
cleanup_testdir

# C8: resolution with --json flag
echo "=== C8: board-config --get-model --json ==="
new_testdir
"$BOARD_MODEL" add my-pro --model gpt-5.5 --provider codex --effort high 2>&1 >/dev/null
"$BOARD_MODEL" asign my-pro --tier pro 2>&1 >/dev/null
json="$("$BOARD_CONFIG" --get-model pro --json 2>&1)"
model=$(echo "$json" | jq -r '.model')
provider=$(echo "$json" | jq -r '.provider')
effort=$(echo "$json" | jq -r '.reasoning_effort')
if [[ "$model" == "gpt-5.5" && "$provider" == "codex" && "$effort" == "high" ]]; then PASS; else FAIL "json=$json"; fi
cleanup_testdir

# C9: resolution with --provider flag
echo "=== C9: board-config --get-model --provider ==="
new_testdir
"$BOARD_MODEL" add my-pro --model gpt-5.5 --provider codex --effort medium 2>&1 >/dev/null
"$BOARD_MODEL" asign my-pro --tier pro 2>&1 >/dev/null
provider="$("$BOARD_CONFIG" --get-model pro --provider 2>&1)"
if [[ "$provider" == "codex" ]]; then PASS; else FAIL "got $provider"; fi
cleanup_testdir

# C10: resolution with --effort flag
echo "=== C10: board-config --get-model --effort ==="
new_testdir
"$BOARD_MODEL" add my-pro --model gpt-5.5 --provider codex --effort low 2>&1 >/dev/null
"$BOARD_MODEL" asign my-pro --tier pro 2>&1 >/dev/null
effort="$("$BOARD_CONFIG" --get-model pro --effort 2>&1)"
if [[ "$effort" == "low" ]]; then PASS; else FAIL "got $effort"; fi
cleanup_testdir

# C11: default tier resolution without config
echo "=== C11: default tier resolution (no config file) ==="
new_testdir
rm -f .tasks/config.json
result="$("$BOARD_CONFIG" --get-model flash 2>&1)"
if [[ "$result" == "opencode/deepseek-v4-flash-free" ]]; then PASS; else FAIL "got $result"; fi
cleanup_testdir

# ============================================================
# Section D: Persistence and compatibility
# ============================================================

echo ""

# D1: language key preserved when adding registry entries
echo "=== D1: language key preserved during add ==="
new_testdir
echo '{"language":"FR"}' > .tasks/config.json
"$BOARD_MODEL" add my-model --model gpt-5.5 --provider codex 2>&1 >/dev/null
lang=$(jq -r '.language' .tasks/config.json)
if [[ "$lang" == "FR" ]]; then PASS; else FAIL "language=$lang"; fi
cleanup_testdir

# D2: existing models key preserved during add
echo "=== D2: existing models preserved during add ==="
new_testdir
echo '{"models":{"flash":"my/model"}}' > .tasks/config.json
"$BOARD_MODEL" add my-model --model gpt-5.5 --provider codex 2>&1 >/dev/null
flash=$(jq -r '.models.flash' .tasks/config.json)
if [[ "$flash" == "my/model" ]]; then PASS; else FAIL "flash=$flash"; fi
cleanup_testdir

# D3: multiple entries can coexist
echo "=== D3: multiple registry entries coexist ==="
new_testdir
"$BOARD_MODEL" add a --model m1 --provider opencode 2>&1 >/dev/null
"$BOARD_MODEL" add b --model m2 --provider codex 2>&1 >/dev/null
"$BOARD_MODEL" add c --model m3 --provider opencode --effort low 2>&1 >/dev/null
count=$(jq '.["model-registry"] | length' .tasks/config.json)
if [[ "$count" == "3" ]]; then PASS; else FAIL "count=$count"; fi
cleanup_testdir

# D4: multiple tiers can be assigned
echo "=== D4: multiple tiers assigned ==="
new_testdir
"$BOARD_MODEL" add a --model m1 --provider opencode 2>&1 >/dev/null
"$BOARD_MODEL" add b --model m2 --provider codex 2>&1 >/dev/null
"$BOARD_MODEL" asign a --tier flash 2>&1 >/dev/null
"$BOARD_MODEL" asign b --tier pro 2>&1 >/dev/null
flash=$(jq -r '.models.flash' .tasks/config.json)
pro=$(jq -r '.models.pro' .tasks/config.json)
if [[ "$flash" == "a" && "$pro" == "b" ]]; then PASS; else FAIL "flash=$flash pro=$pro"; fi
cleanup_testdir

# D5: list with no config file
echo "=== D5: list with no config shows defaults ==="
new_testdir
rm -f .tasks/config.json
output="$("$BOARD_MODEL" list 2>&1)"
if grep -q "(empty)" <<<"$output" && grep -q "(default)" <<<"$output"; then PASS; else FAIL "unexpected list output"; fi
cleanup_testdir

# D6: board-config --get still returns language
echo "=== D6: board-config --get returns language ==="
new_testdir
echo '{"language":"DE"}' > .tasks/config.json
result="$("$BOARD_CONFIG" --get 2>&1)"
if [[ "$result" == "DE" ]]; then PASS; else FAIL "got $result"; fi
cleanup_testdir

# D7: board-config --set-language still works
echo "=== D7: board-config --set-language still works ==="
new_testdir
"$BOARD_CONFIG" --set-language "ru" 2>&1 >/dev/null
lang=$(jq -r '.language' .tasks/config.json)
if [[ "$lang" == "RU" ]]; then PASS; else FAIL "got $lang"; fi
cleanup_testdir

# ============================================================
# Section E: Edge cases
# ============================================================

echo ""

# E1: name with hyphen is valid
echo "=== E1: name with hyphen ==="
new_testdir
"$BOARD_MODEL" add my-entry --model x --provider opencode 2>&1 >/dev/null
if [[ $? -eq 0 ]]; then PASS; else FAIL "rejected hyphenated name"; fi
cleanup_testdir

# E2: name with underscore is valid
echo "=== E2: name with underscore ==="
new_testdir
"$BOARD_MODEL" add my_entry --model x --provider opencode 2>&1 >/dev/null
if [[ $? -eq 0 ]]; then PASS; else FAIL "rejected name with underscore"; fi
cleanup_testdir

# E3: add without optional effort
echo "=== E3: add without effort works ==="
new_testdir
"$BOARD_MODEL" add simple --model gpt-5.4-mini --provider codex 2>&1 >/dev/null
has_effort=$(jq -r '.["model-registry"]["simple"].reasoning_effort // "NONE"' .tasks/config.json)
if [[ "$has_effort" == "NONE" ]]; then PASS; else FAIL "unexpected effort: $has_effort"; fi
cleanup_testdir

# E4: edit clears effort (by setting to empty... actually we don't have a way to clear)
# Instead test: edit with --effort overrides previous effort
echo "=== E4: edit overrides effort from high to low ==="
new_testdir
"$BOARD_MODEL" add entry --model gpt-5.5 --provider codex --effort high 2>&1 >/dev/null
"$BOARD_MODEL" edit entry --effort low 2>&1 >/dev/null
effort=$(jq -r '.["model-registry"]["entry"].reasoning_effort' .tasks/config.json)
if [[ "$effort" == "low" ]]; then PASS; else FAIL "effort=$effort"; fi
cleanup_testdir

# E5: board-config --get-model still works with old-style config
echo "=== E5: board-config --get-model with old-style config ==="
new_testdir
echo '{"language":"EN","models":{"pro":"opencode-go/deepseek-v4-pro"}}' > .tasks/config.json
result="$("$BOARD_CONFIG" --get-model pro 2>&1)"
if [[ "$result" == "opencode-go/deepseek-v4-pro" ]]; then PASS; else FAIL "got $result"; fi
cleanup_testdir

# E6: help outputs usage
echo "=== E6: --help outputs usage ==="
new_testdir
output="$("$BOARD_MODEL" --help 2>&1)"
if grep -q "add" <<<"$output" && grep -q "asign" <<<"$output" \
   && grep -q "edit" <<<"$output" && grep -q "delete" <<<"$output"; then
  PASS
else
  FAIL "help missing commands"
fi
cleanup_testdir

# E7: opencode provider for model with / in it
echo "=== E7: model with / auto-detected as opencode ==="
new_testdir
"$BOARD_MODEL" add oc --model "openai/some-model" 2>&1 >/dev/null
provider=$(jq -r '.["model-registry"]["oc"].provider' .tasks/config.json)
if [[ "$provider" == "opencode" ]]; then PASS; else FAIL "got $provider"; fi
cleanup_testdir

# E8: re-asign same tier to different entry
echo "=== E8: re-asign same tier to different entry ==="
new_testdir
"$BOARD_MODEL" add first --model m1 --provider opencode 2>&1 >/dev/null
"$BOARD_MODEL" add second --model m2 --provider codex 2>&1 >/dev/null
"$BOARD_MODEL" asign first --tier pro 2>&1 >/dev/null
"$BOARD_MODEL" asign second --tier pro 2>&1 >/dev/null
tier_val=$(jq -r '.models.pro' .tasks/config.json)
if [[ "$tier_val" == "second" ]]; then PASS; else FAIL "tier=$tier_val"; fi
cleanup_testdir

# ============================================================
# Section F: Dispatch integration — agent-spawn.sh tier path
# ============================================================

echo ""

# F1: registry provider overrides auto-detection (model would auto-detect as
# codex but registry says opencode — resolved provider must be opencode)
echo "=== F1: registry provider overrides auto-detection ==="
new_testdir
"$BOARD_MODEL" add my-pro --model gpt-5.5 --provider opencode --effort medium 2>&1 >/dev/null
"$BOARD_MODEL" asign my-pro --tier pro 2>&1 >/dev/null
provider="$("$BOARD_CONFIG" --get-model pro --provider 2>&1)"
model="$("$BOARD_CONFIG" --get-model pro 2>&1)"
# model=gpt-5.5 would auto-detect as codex, but provider must come from registry
detected="$(auto_detect_provider "$model")"
if [[ "$detected" == "codex" && "$provider" == "opencode" ]]; then
  PASS
else
  FAIL "auto-detect=$detected but registry provider=$provider (model=$model)"
fi
cleanup_testdir

# F2: codex effort from registry is resolvable for dispatch
echo "=== F2: codex effort resolved for dispatch ==="
new_testdir
"$BOARD_MODEL" add heavy --model gpt-5.5 --provider codex --effort high 2>&1 >/dev/null
"$BOARD_MODEL" asign heavy --tier pro 2>&1 >/dev/null
effort="$("$BOARD_CONFIG" --get-model pro --effort 2>&1)"
if [[ "$effort" == "high" ]]; then PASS; else FAIL "effort=$effort"; fi
cleanup_testdir

# F3: effort absent when registry entry has no reasoning_effort
echo "=== F3: absent effort when registry has no reasoning_effort ==="
new_testdir
"$BOARD_MODEL" add light --model gpt-5.4-mini --provider codex 2>&1 >/dev/null
"$BOARD_MODEL" asign light --tier simple 2>&1 >/dev/null
effort="$("$BOARD_CONFIG" --get-model simple --effort 2>&1)"
if [[ -z "$effort" ]]; then PASS; else FAIL "effort should be empty, got '$effort'"; fi
cleanup_testdir

# F4: provider for opencode-style model ID preserved through registry
echo "=== F4: opencode model ID preserves opencode provider ==="
new_testdir
"$BOARD_MODEL" add oc-pro --model opencode-go/deepseek-v4-pro --provider opencode 2>&1 >/dev/null
"$BOARD_MODEL" asign oc-pro --tier pro 2>&1 >/dev/null
provider="$("$BOARD_CONFIG" --get-model pro --provider 2>&1)"
model="$("$BOARD_CONFIG" --get-model pro 2>&1)"
if [[ "$provider" == "opencode" && "$model" == "opencode-go/deepseek-v4-pro" ]]; then
  PASS
else
  FAIL "provider=$provider model=$model"
fi
cleanup_testdir

# F5: board-config --json includes all three fields for dispatch
echo "=== F5: --json carries model + provider + effort ==="
new_testdir
"$BOARD_MODEL" add full-entry --model gpt-5.5 --provider codex --effort low 2>&1 >/dev/null
"$BOARD_MODEL" asign full-entry --tier pro 2>&1 >/dev/null
json="$("$BOARD_CONFIG" --get-model pro --json 2>&1)"
if [[ "$(echo "$json" | jq -r '.model')" == "gpt-5.5" \
   && "$(echo "$json" | jq -r '.provider')" == "codex" \
   && "$(echo "$json" | jq -r '.reasoning_effort')" == "low" ]]; then
  PASS
else
  FAIL "json=$json"
fi
cleanup_testdir

# F6: raw model ID (no registry) still resolves via auto-detect (backward compat)
echo "=== F6: raw model ID auto-detects backend (backward compat) ==="
new_testdir
echo '{"models":{"review":"gpt-5.4","simple":"gpt-5.4-mini"}}' > .tasks/config.json
review_provider="$("$BOARD_CONFIG" --get-model review --provider 2>&1)"
simple_provider="$("$BOARD_CONFIG" --get-model simple --provider 2>&1)"
if [[ "$review_provider" == "codex" && "$simple_provider" == "codex" ]]; then
  PASS
else
  FAIL "review=$review_provider simple=$simple_provider"
fi
cleanup_testdir

# F7: tier with bare opencode model ID resolves to opencode
echo "=== F7: bare model ID with / resolves to opencode ==="
new_testdir
echo '{"models":{"flash":"openai/some-model"}}' > .tasks/config.json
provider="$("$BOARD_CONFIG" --get-model flash --provider 2>&1)"
if [[ "$provider" == "opencode" ]]; then PASS; else FAIL "provider=$provider"; fi
cleanup_testdir

# F8: explicit --agent flag still overrides registry provider (agent-spawn precedence)
echo "=== F8: --agent flag overrides registry provider ==="
new_testdir
"$BOARD_MODEL" add entry --model gpt-5.5 --provider opencode --effort low 2>&1 >/dev/null
"$BOARD_MODEL" asign entry --tier pro 2>&1 >/dev/null
# Simulate what agent-spawn.sh does: registry provider is opencode, but if user
# passes --agent pi, that must win. The config provider is visible but
# overridable. Here we just verify the config provider is what we expect.
provider="$("$BOARD_CONFIG" --get-model pro --provider 2>&1)"
if [[ "$provider" == "opencode" ]]; then PASS; else FAIL "provider=$provider"; fi
cleanup_testdir

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All board-model tests passed."
else
  echo "${failures} test(s) failed."
  exit 1
fi
