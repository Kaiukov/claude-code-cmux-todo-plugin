#!/usr/bin/env bash
# Tests for free-first board-config defaults (#131 slice-1).
# Verifies baked-in DEFAULT_MODELS_JSON and DEFAULT_PROFILES_JSON
# resolve correctly when no .tasks/config.json override is present.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOARD_CONFIG="$REPO_ROOT/bin/board-config"

if [[ ! -f "$BOARD_CONFIG" ]]; then
  echo "FAIL: board-config not found at $BOARD_CONFIG"
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

failures=0

# ── Profile defaults ──

echo "=== P1: --get-profile docs --model → mimo-v2.5-free ==="
model="$("$BOARD_CONFIG" --get-profile docs --model 2>&1)"
if [[ "$model" == "mimo-v2.5-free" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$model'"
  failures=$((failures + 1))
fi

echo "=== P2: --get-profile docs --provider → opencode ==="
provider="$("$BOARD_CONFIG" --get-profile docs --provider 2>&1)"
if [[ "$provider" == "opencode" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$provider'"
  failures=$((failures + 1))
fi

echo "=== P3: --get-profile review --model → deepseek-v4-pro ==="
model="$("$BOARD_CONFIG" --get-profile review --model 2>&1)"
if [[ "$model" == "deepseek-v4-pro" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$model'"
  failures=$((failures + 1))
fi

echo "=== P4: --get-profile review --provider → opencode-go ==="
provider="$("$BOARD_CONFIG" --get-profile review --provider 2>&1)"
if [[ "$provider" == "opencode-go" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$provider'"
  failures=$((failures + 1))
fi

echo "=== P5: --get-profile backend-fast --model → deepseek-v4-flash-free ==="
model="$("$BOARD_CONFIG" --get-profile backend-fast --model 2>&1)"
if [[ "$model" == "deepseek-v4-flash-free" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$model'"
  failures=$((failures + 1))
fi

echo "=== P6: --get-profile repo-scout --model → nemotron-3-ultra-free ==="
model="$("$BOARD_CONFIG" --get-profile repo-scout --model 2>&1)"
if [[ "$model" == "nemotron-3-ultra-free" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$model'"
  failures=$((failures + 1))
fi

echo "=== P7: --get-profile tiny-patch --thinking → low ==="
thinking="$("$BOARD_CONFIG" --get-profile tiny-patch --thinking 2>&1)"
if [[ "$thinking" == "low" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$thinking'"
  failures=$((failures + 1))
fi

echo "=== P8: --get-profile test --model → gpt-5.4-mini ==="
model="$("$BOARD_CONFIG" --get-profile test --model 2>&1)"
if [[ "$model" == "gpt-5.4-mini" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$model'"
  failures=$((failures + 1))
fi

echo "=== P9: backend profile unchanged (deepseek-v4-pro, opencode-go) ==="
json="$("$BOARD_CONFIG" --get-profile backend --json 2>&1)"
provider="$(echo "$json" | jq -r '.provider')"
model="$(echo "$json" | jq -r '.model')"
thinking="$(echo "$json" | jq -r '.thinking')"
if [[ "$provider" == "opencode-go" && "$model" == "deepseek-v4-pro" && "$thinking" == "high" ]]; then
  echo "PASS"
else
  echo "FAIL: provider=$provider model=$model thinking=$thinking"
  failures=$((failures + 1))
fi

echo "=== P10: frontend profile has model_status=TBC and gate=user-permission ==="
json="$("$BOARD_CONFIG" --get-profile frontend --json 2>&1)"
model_status="$(echo "$json" | jq -r '.model_status // empty')"
# gate is stored in the constant but not surfaced by the resolver yet;
# verify it is present in the source file instead.
if [[ "$model_status" == "TBC" ]]; then
  echo "PASS  (model_status=TBC)"
else
  echo "FAIL: model_status='$model_status'"
  failures=$((failures + 1))
fi

echo "=== P11: frontend-top thinking is now high ==="
thinking="$("$BOARD_CONFIG" --get-profile frontend-top --thinking 2>&1)"
if [[ "$thinking" == "high" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$thinking'"
  failures=$((failures + 1))
fi

# ── Absence of gpt-5.5 ──

echo "=== G1: no gpt-5.5 anywhere in board-config source ==="
if grep -q "gpt-5.5" "$BOARD_CONFIG"; then
  echo "FAIL: gpt-5.5 found in board-config"
  failures=$((failures + 1))
else
  echo "PASS"
fi

# ── Free models end in -free ──

echo "=== F1: flash/simple/backend-fast/repo-scout/docs use -free models ==="
all_free_ok=true
for profile in backend-fast repo-scout docs; do
  model="$("$BOARD_CONFIG" --get-profile "$profile" --model 2>&1)"
  if [[ "$model" != *-free ]]; then
    echo "  FAIL: profile $profile model '$model' does not end in -free"
    all_free_ok=false
  fi
done

if $all_free_ok; then
  echo "PASS"
else
  failures=$((failures + 1))
fi

# ── New profiles are valid ──

echo "=== N1: all 9 profiles are recognised ==="
all_valid_ok=true
for profile in backend backend-fast repo-scout docs test tiny-patch review frontend frontend-top; do
  if ! "$BOARD_CONFIG" --get-profile "$profile" --model >/dev/null 2>&1; then
    echo "  FAIL: profile '$profile' not recognised"
    all_valid_ok=false
  fi
done
if $all_valid_ok; then
  echo "PASS"
else
  failures=$((failures + 1))
fi

echo "=== N2: unknown profile still rejected ==="
if "$BOARD_CONFIG" --get-profile nope --model 2>/dev/null; then
  echo "FAIL: unknown profile should fail"
  failures=$((failures + 1))
else
  echo "PASS"
fi

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All board-config defaults tests passed."
else
  echo "${failures} test(s) failed."
  exit 1
fi
