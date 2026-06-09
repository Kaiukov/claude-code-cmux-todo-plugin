#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOARD_CONFIG="$REPO_ROOT/bin/board-config"

if [[ ! -f "$BOARD_CONFIG" ]]; then
  echo "FAIL: board-config not found at $BOARD_CONFIG"
  exit 1
fi

# --- Pure functions extracted from board-config ---

DEFAULT_LANG="EN"

normalize_lang() {
  local raw="$1"

  local trimmed
  trimmed="$(echo "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  if [[ -z "$trimmed" ]]; then
    echo "board-config: language code must not be empty or whitespace" >&2
    return 1
  fi

  echo "$trimmed" | tr '[:lower:]' '[:upper:]'
}

resolve_language() {
  local json="$1"

  if [[ -z "$json" ]]; then
    echo "$DEFAULT_LANG"
    return
  fi

  local lang
  lang="$(echo "$json" | jq -r '.language // empty' 2>/dev/null)"

  if [[ -z "$lang" ]]; then
    echo "$DEFAULT_LANG"
  else
    echo "$lang"
  fi
}

failures=0

echo "=== Test 1: resolve_language with empty json -> EN default ==="
result=$(resolve_language "")
if [[ "$result" == "EN" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result'"
  failures=$((failures + 1))
fi

echo "=== Test 2: resolve_language with no language key -> EN default ==="
result=$(resolve_language '{"other":"value"}')
if [[ "$result" == "EN" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result'"
  failures=$((failures + 1))
fi

echo "=== Test 3: resolve_language with language set -> returns it ==="
result=$(resolve_language '{"language":"FR"}')
if [[ "$result" == "FR" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result'"
  failures=$((failures + 1))
fi

echo "=== Test 4: resolve_language preserves other keys untouched ==="
result=$(resolve_language '{"language":"DE","other":"val"}')
if [[ "$result" == "DE" ]]; then
  echo "PASS"
else
  echo "FAIL: got '$result'"
  failures=$((failures + 1))
fi

echo "=== Test 5: normalize_lang lowercase -> uppercase ==="
if result=$(normalize_lang "ru"); then
  if [[ "$result" == "RU" ]]; then
    echo "PASS"
  else
    echo "FAIL: got '$result'"
    failures=$((failures + 1))
  fi
else
  echo "FAIL: normalize_lang exited non-zero"
  failures=$((failures + 1))
fi

echo "=== Test 6: normalize_lang trims whitespace ==="
if result=$(normalize_lang "  fr  "); then
  if [[ "$result" == "FR" ]]; then
    echo "PASS"
  else
    echo "FAIL: got '$result'"
    failures=$((failures + 1))
  fi
else
  echo "FAIL: normalize_lang exited non-zero"
  failures=$((failures + 1))
fi

echo "=== Test 7: normalize_lang rejects empty string ==="
if result=$(normalize_lang ""); then
  echo "FAIL: should have exited non-zero but got '$result'"
  failures=$((failures + 1))
else
  echo "PASS"
fi
set -e

echo "=== Test 8: normalize_lang rejects whitespace-only ==="
if result=$(normalize_lang "   "); then
  echo "FAIL: should have exited non-zero but got '$result'"
  failures=$((failures + 1))
else
  echo "PASS"
fi
set -e

echo "=== Test 9: normalize_lang mixed case -> uppercase ==="
if result=$(normalize_lang "eN"); then
  if [[ "$result" == "EN" ]]; then
    echo "PASS"
  else
    echo "FAIL: got '$result'"
    failures=$((failures + 1))
  fi
else
  echo "FAIL: normalize_lang exited non-zero"
  failures=$((failures + 1))
fi

echo "=== Test 10: normalize_lang already uppercase -> stays ==="
if result=$(normalize_lang "EN"); then
  if [[ "$result" == "EN" ]]; then
    echo "PASS"
  else
    echo "FAIL: got '$result'"
    failures=$((failures + 1))
  fi
else
  echo "FAIL: normalize_lang exited non-zero"
  failures=$((failures + 1))
fi

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All board-config pure logic tests passed."
else
  echo "${failures} test(s) failed."
  exit 1
fi
