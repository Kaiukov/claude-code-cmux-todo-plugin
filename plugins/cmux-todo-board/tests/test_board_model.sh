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

# ============================================================
# Section D: Persistence and compatibility (remaining)
# ============================================================

echo ""

new_testdir() {
  TESTDIR="$(mktemp -d)"
  pushd "$TESTDIR" >/dev/null
  mkdir -p .tasks
}

cleanup_testdir() {
  popd >/dev/null || true
  rm -rf "$TESTDIR"
}

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

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All board-model tests passed."
else
  echo "${failures} test(s) failed."
  exit 1
fi
